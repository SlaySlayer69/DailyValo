import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/storage_keys.dart';
import '../core/network/riot_session_manager.dart';
import '../core/network/webview_cookie_reader.dart';
import '../core/storage/local_store.dart';
import '../core/storage/secure_token_store.dart';
import '../core/utils/logger.dart';
import '../features/auth/data/account_registry.dart';
import '../features/auth/data/datasources/riot_auth_api.dart';
import '../features/auth/data/models/account.dart';
import '../features/auth/data/models/riot_session.dart';
import '../features/content/data/models/content_catalog.dart';
import '../features/content/data/models/weapon_skin.dart';
import '../features/content/data/repositories/content_repository.dart';
import '../features/player/data/models/player_profile.dart';
import '../features/player/data/repositories/player_repository.dart';
import '../features/store/data/models/shop.dart';
import '../features/store/data/models/shop_sightings.dart';
import '../features/store/data/repositories/store_repository.dart';
import '../features/wishlist/data/models/wishlist_entry.dart';
import '../features/wishlist/data/repositories/wishlist_repository.dart';
import '../features/wishlist/data/wishlist_transfer.dart';
import '../services/background/background_scheduler.dart';
import '../services/notifications/notification_service.dart';
import '../services/widgets/home_widget_service.dart';
import 'dependencies.dart';

// -----------------------------------------------------------------------------
// Object graph
// -----------------------------------------------------------------------------

/// The graph the UI is currently driven by, and the ability to swap it.
///
/// Riverpod is used as a *view* over [AppDependencies], not as the container
/// itself — see the note on that class for why the graph has to exist outside
/// the widget tree.
///
/// It is a notifier rather than a constant because the graph is scoped to one
/// account. Switching accounts does not mutate it; it builds a second one and
/// puts that in its place, and every provider below rebuilds off the new
/// stores. Repositories therefore never need to know that accounts can change.
class AppGraph extends Notifier<AppDependencies> {
  AppGraph(this._initial);

  final AppDependencies _initial;

  @override
  AppDependencies build() => _initial;

  /// Points the app at another signed-in account.
  Future<void> switchTo(Account account) async {
    await state.accounts.setActive(account.puuid);
    await _rebuild(account);
  }

  /// Rebuilds against whichever account the registry now considers active —
  /// after a sign-in, or after one account has been signed out.
  Future<void> reload() => _rebuild(state.accounts.active);

  Future<void> _rebuild(Account? account) async {
    final AppDependencies next = await AppDependencies.bootstrap(
      forAccount: account,
    );
    // A fresh graph means fresh stores; the widget tree must not keep showing
    // the previous account's shop, header or collection while they load.
    state = next;
    ref.invalidate(shopControllerProvider);
    ref.invalidate(playerControllerProvider);
    ref.invalidate(ownedSkinsProvider);
    ref.invalidate(ownedAccessoriesProvider);
    ref.invalidate(wishlistControllerProvider);
  }
}

final NotifierProvider<AppGraph, AppDependencies> appDependenciesProvider =
    NotifierProvider<AppGraph, AppDependencies>(
      () => throw UnimplementedError(
        'appDependenciesProvider must be overridden in main().',
      ),
    );

/// The accounts signed in on this device, and which one is showing.
final Provider<AccountRegistry> accountRegistryProvider =
    Provider<AccountRegistry>(
      (Ref ref) => ref.watch(appDependenciesProvider).accounts,
    );

final Provider<Account> activeAccountProvider = Provider<Account>(
  (Ref ref) => ref.watch(appDependenciesProvider).account,
);

final Provider<LocalStore> localStoreProvider = Provider<LocalStore>(
  (Ref ref) => ref.watch(appDependenciesProvider).localStore,
);

final Provider<RiotAuthApi> authApiProvider = Provider<RiotAuthApi>(
  (Ref ref) => ref.watch(appDependenciesProvider).authApi,
);

final ChangeNotifierProvider<RiotSessionManager> sessionManagerProvider =
    ChangeNotifierProvider<RiotSessionManager>(
      (Ref ref) => ref.watch(appDependenciesProvider).sessions,
    );

final Provider<ContentRepository> contentRepositoryProvider =
    Provider<ContentRepository>(
      (Ref ref) => ref.watch(appDependenciesProvider).content,
    );

final Provider<StoreRepository> storeRepositoryProvider =
    Provider<StoreRepository>(
      (Ref ref) => ref.watch(appDependenciesProvider).store,
    );

final Provider<WishlistRepository> wishlistRepositoryProvider =
    Provider<WishlistRepository>(
      (Ref ref) => ref.watch(appDependenciesProvider).wishlist,
    );

final Provider<PlayerRepository> playerRepositoryProvider =
    Provider<PlayerRepository>(
      (Ref ref) => ref.watch(appDependenciesProvider).player,
    );

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>(
      (Ref ref) => ref.watch(appDependenciesProvider).notifications,
    );

// -----------------------------------------------------------------------------
// App mode
// -----------------------------------------------------------------------------

/// How the app is currently sourcing data.
enum AppMode {
  /// No session and demo mode off — show the login screen.
  signedOut,

  /// Synthesised offers over the real content catalogue.
  demo,

  /// A live Riot session.
  live,
}

/// Owns the sign-in / demo / sign-out transitions, including the side effects
/// (scheduling background work, clearing caches) that go with them.
class AppModeController extends Notifier<AppMode> {
  @override
  AppMode build() {
    // Rebuild whenever the session manager notifies, so a token wipe in the
    // interceptor drops the UI back to the login screen on its own.
    final RiotSessionManager sessions = ref.watch(sessionManagerProvider);
    final LocalStore store = ref.watch(localStoreProvider);

    if (sessions.isAuthenticated) return AppMode.live;
    if (store.setting<bool>(SettingKeys.demoMode, false)) return AppMode.demo;
    return AppMode.signedOut;
  }

  /// Enters the credential-free demo mode.
  Future<void> enterDemoMode() async {
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, true);
    ref.invalidateSelf();
    await _onEnteredApp();
  }

  /// Called after a successful sign-in, with the session that produced it.
  ///
  /// Registers the account and rebuilds the graph around it, so this is both
  /// "signed in" and "added another account" — from here they are the same
  /// operation, which is why adding one needs no separate path.
  Future<void> onSignedIn(RiotSession session) async {
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, false);
    await ref.read(accountRegistryProvider).upsert(session);
    await ref.read(appDependenciesProvider.notifier).reload();

    // Riot's own jar still holds the session that was just used. Left there,
    // "Add account" would sail past the login page and add the same account
    // again; our copy of the cookie is already in the keystore, so dropping it
    // costs nothing.
    await const WebViewCookieReader().clear();

    ref.invalidateSelf();
    await _onEnteredApp();
  }

  /// Signs out the account on screen, and moves to another if there is one.
  Future<void> signOut() async {
    final AppDependencies deps = ref.read(appDependenciesProvider);
    final Account leaving = deps.account;

    // This account's notifications, not everyone's — the ids are per account
    // exactly so one sign-out cannot silence the rest.
    await deps.notifications.cancelForThisAccount();
    await const WebViewCookieReader().clear();
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, false);
    await ref.read(sessionManagerProvider).signOut();

    if (leaving.puuid.isNotEmpty) {
      await deps.accounts.remove(leaving.puuid, deps.secureStore);
    }

    final bool anyLeft = !deps.accounts.isEmpty;
    if (!anyLeft) {
      await BackgroundScheduler.cancelAll();
      // Someone else's shop must not stay on the home screen of a signed-out
      // phone.
      await HomeWidgetService.clear();
    }

    await ref.read(appDependenciesProvider.notifier).reload();
    ref.invalidateSelf();
  }

  /// Signs every account out and returns the device to the login screen.
  Future<void> signOutAll() async {
    final AppDependencies deps = ref.read(appDependenciesProvider);

    await BackgroundScheduler.cancelAll();
    await deps.notifications.cancelEverything();
    await HomeWidgetService.clear();
    await const WebViewCookieReader().clear();
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, false);
    await ref.read(sessionManagerProvider).signOut();

    for (final Account account in deps.accounts.all()) {
      await deps.accounts.remove(
        account.puuid,
        SecureTokenStore(accountId: account.puuid),
      );
    }

    await ref.read(appDependenciesProvider.notifier).reload();
    ref.invalidateSelf();
  }

  /// Points the app at another signed-in account.
  Future<void> switchTo(Account account) async {
    await ref.read(appDependenciesProvider.notifier).switchTo(account);
    ref.invalidateSelf();
  }

  Future<void> _onEnteredApp() async {
    final NotificationService notifications = ref.read(
      notificationServiceProvider,
    );
    await notifications.requestPermission();
    await BackgroundScheduler.registerPeriodicCheck();
  }
}

final NotifierProvider<AppModeController, AppMode> appModeProvider =
    NotifierProvider<AppModeController, AppMode>(AppModeController.new);

// -----------------------------------------------------------------------------
// Content
// -----------------------------------------------------------------------------

/// The static catalogue. Everything else joins against this.
final FutureProvider<ContentCatalog> contentCatalogProvider =
    FutureProvider<ContentCatalog>(
      (Ref ref) => ref.watch(contentRepositoryProvider).getCatalog(),
    );

// -----------------------------------------------------------------------------
// Shop
// -----------------------------------------------------------------------------

class ShopController extends AsyncNotifier<Shop> {
  @override
  Future<Shop> build() async {
    // Re-resolve whenever the wishlist changes so the heart on a shop card and
    // the "on your wishlist" banner stay in sync without a manual refresh.
    ref.watch(wishlistControllerProvider);

    // Awaited before the shop is resolved, not alongside it: ownership is read
    // out of the cache by `getShop`, so resolving first would produce a shop
    // with nothing marked and only fix itself on the next rebuild.
    await ref.watch(ownedAccessoriesProvider.future);

    return ref.read(storeRepositoryProvider).getShop();
  }

  /// Pull-to-refresh. Keeps the previous shop on screen while loading so the
  /// grid does not collapse to a spinner.
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(storeRepositoryProvider).getShop(forceRefresh: true),
    );
  }
}

final AsyncNotifierProvider<ShopController, Shop> shopControllerProvider =
    AsyncNotifierProvider<ShopController, Shop>(ShopController.new);

// -----------------------------------------------------------------------------
// Drought counter
// -----------------------------------------------------------------------------

/// The skins on offer right now, by skin UUID.
///
/// Keyed by skin rather than by offer id, because everything that asks this
/// question — the catalogue, the detail page, the wishlist — holds a skin.
final Provider<Set<String>> skinsInShopTodayProvider = Provider<Set<String>>((
  Ref ref,
) {
  final Shop? shop = ref.watch(shopControllerProvider).valueOrNull;
  if (shop == null) return const <String>{};
  return shop.dailyOffers.map((ShopOffer o) => o.skin.uuid).toSet();
});

/// Every sighting recorded for the active account.
///
/// Watches the shop controller because that is what writes them: a resolved
/// shop records today's offers, and this has to be re-read afterwards or the
/// detail page would still say "not seen" about a skin sitting in the grid
/// behind it.
final Provider<ShopSightings> shopSightingsProvider = Provider<ShopSightings>((
  Ref ref,
) {
  ref.watch(shopControllerProvider);
  return ref.watch(storeRepositoryProvider).readSightings(DateTime.now());
});

/// How long the user has been waiting for one particular skin.
final ProviderFamily<SkinAvailability, String> skinAvailabilityProvider =
    Provider.family<SkinAvailability, String>((Ref ref, String skinUuid) {
      return SkinAvailability.of(
        skinUuid: skinUuid,
        inShopToday: ref.watch(skinsInShopTodayProvider),
        sightings: ref.watch(shopSightingsProvider),
        now: DateTime.now(),
      );
    });

// -----------------------------------------------------------------------------
// Player header
// -----------------------------------------------------------------------------

class PlayerController extends AsyncNotifier<PlayerProfile> {
  bool _disposed = false;

  @override
  Future<PlayerProfile> build() async {
    final PlayerRepository repository = ref.watch(playerRepositoryProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    // Show the cached profile immediately, then let the refresh land on top.
    final PlayerProfile? cached = repository.cached;
    if (cached != null) {
      unawaited(_backfill(repository));
      return cached;
    }
    return repository.refresh();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(playerRepositoryProvider).refresh(),
    );
  }

  /// Silent refresh behind an already-rendered cached profile. A failure here
  /// is not worth an error state — the header is already showing real data.
  Future<void> _backfill(PlayerRepository repository) async {
    try {
      final PlayerProfile fresh = await repository.refresh();
      if (!_disposed) state = AsyncData<PlayerProfile>(fresh);
    } on Object {
      // Intentionally swallowed; see above.
    }
  }
}

final AsyncNotifierProvider<PlayerController, PlayerProfile>
playerControllerProvider =
    AsyncNotifierProvider<PlayerController, PlayerProfile>(
      PlayerController.new,
    );

// -----------------------------------------------------------------------------
// Wishlist
// -----------------------------------------------------------------------------

class WishlistController extends Notifier<List<WishlistEntry>> {
  @override
  List<WishlistEntry> build() =>
      ref.watch(wishlistRepositoryProvider).getAll();

  /// Returns the skin's new wishlist state.
  Future<bool> toggle(WeaponSkin skin) async {
    final bool added = await ref.read(wishlistRepositoryProvider).toggle(skin);
    state = ref.read(wishlistRepositoryProvider).getAll();
    return added;
  }

  Future<void> remove(String skinUuid) async {
    await ref.read(wishlistRepositoryProvider).remove(skinUuid);
    state = ref.read(wishlistRepositoryProvider).getAll();
  }

  /// Undoes a [remove], restoring the entry's original position.
  Future<void> restore(WishlistEntry entry) async {
    await ref.read(wishlistRepositoryProvider).restore(entry);
    state = ref.read(wishlistRepositoryProvider).getAll();
  }

  /// Merges an exported wishlist into this one.
  Future<ImportResult> import(List<WishlistEntry> entries) async {
    final ImportResult result = await ref
        .read(wishlistRepositoryProvider)
        .importEntries(entries);
    state = ref.read(wishlistRepositoryProvider).getAll();
    return result;
  }

  bool contains(String skinUuid) =>
      state.any((WishlistEntry e) => e.skinUuid == skinUuid);
}

final NotifierProvider<WishlistController, List<WishlistEntry>>
wishlistControllerProvider =
    NotifierProvider<WishlistController, List<WishlistEntry>>(
      WishlistController.new,
    );

/// Whether a given skin is wishlisted. Scoped per skin so a heart tap rebuilds
/// one card rather than the whole grid.
final ProviderFamily<bool, String> isWishlistedProvider =
    Provider.family<bool, String>((Ref ref, String skinUuid) {
      return ref
          .watch(wishlistControllerProvider)
          .any((WishlistEntry e) => e.skinUuid == skinUuid);
    });

// -----------------------------------------------------------------------------
// Collection
// -----------------------------------------------------------------------------

/// Level UUIDs of every skin the player owns.
final FutureProvider<Set<String>> ownedSkinsProvider =
    FutureProvider<Set<String>>((Ref ref) async {
      final StoreRepository repository = ref.watch(storeRepositoryProvider);
      final Set<String> cached = repository.readCachedOwnedSkins();
      if (cached.isNotEmpty) return cached;
      return repository.refreshOwnedSkins();
    });

/// UUIDs of every spray, buddy, card and title the player owns.
///
/// Fetched on the same terms as the skins — cache first, network only when
/// there is nothing yet — and swallowing a failure rather than propagating it.
/// An ownership marker is a nicety; the Accessory Store has to render whether
/// or not the entitlements calls answered, and an empty set simply means
/// nothing is marked.
final FutureProvider<Set<String>> ownedAccessoriesProvider =
    FutureProvider<Set<String>>((Ref ref) async {
      final StoreRepository repository = ref.watch(storeRepositoryProvider);
      final Set<String> cached = repository.readCachedOwnedAccessories();
      if (cached.isNotEmpty) return cached;
      try {
        return await repository.refreshOwnedAccessories();
      } on Object catch (e) {
        Log.d('Store', 'Owned accessories unavailable: $e');
        return <String>{};
      }
    });

/// The owned skins, resolved and sorted by rarity then name.
final FutureProvider<List<WeaponSkin>> collectionProvider =
    FutureProvider<List<WeaponSkin>>((Ref ref) async {
      final ContentCatalog catalog = await ref.watch(
        contentCatalogProvider.future,
      );
      final Set<String> owned = await ref.watch(ownedSkinsProvider.future);

      final List<WeaponSkin> skins = owned
          .map(catalog.skinByOfferUuid)
          .whereType<WeaponSkin>()
          .where((WeaponSkin s) => s.isPurchasable)
          .toSet()
          .toList();

      skins.sort((WeaponSkin a, WeaponSkin b) {
        final int rankA = catalog.tierOf(a)?.rank ?? -1;
        final int rankB = catalog.tierOf(b)?.rank ?? -1;
        if (rankA != rankB) return rankB.compareTo(rankA);
        return a.displayName.compareTo(b.displayName);
      });
      return skins;
    });

/// The collection as *skin* UUIDs, for "do I own this?".
///
/// [ownedSkinsProvider] holds skin *level* UUIDs, which is what the entitlements
/// endpoint returns and what the storefront quotes — neither is the id anything
/// in the UI holds. Resolving once here beats every caller walking a skin's
/// levels against the raw set.
///
/// Empty while the collection is still loading, which reads as "not owned" —
/// the honest default: an owned marker that has not arrived yet is missing, and
/// a missing marker is better than a wrong one.
final Provider<Set<String>> ownedSkinUuidsProvider = Provider<Set<String>>((
  Ref ref,
) {
  final List<WeaponSkin>? owned = ref.watch(collectionProvider).valueOrNull;
  if (owned == null) return const <String>{};
  return owned.map((WeaponSkin s) => s.uuid).toSet();
});
