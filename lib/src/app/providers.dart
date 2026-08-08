import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/storage_keys.dart';
import '../core/network/riot_session_manager.dart';
import '../core/network/webview_cookie_reader.dart';
import '../core/storage/local_store.dart';
import '../features/auth/data/datasources/riot_auth_api.dart';
import '../features/content/data/models/content_catalog.dart';
import '../features/content/data/models/weapon_skin.dart';
import '../features/content/data/repositories/content_repository.dart';
import '../features/player/data/models/player_profile.dart';
import '../features/player/data/repositories/player_repository.dart';
import '../features/store/data/models/shop.dart';
import '../features/store/data/repositories/store_repository.dart';
import '../features/wishlist/data/models/wishlist_entry.dart';
import '../features/wishlist/data/repositories/wishlist_repository.dart';
import '../services/background/background_scheduler.dart';
import '../services/notifications/notification_service.dart';
import 'dependencies.dart';

// -----------------------------------------------------------------------------
// Object graph
// -----------------------------------------------------------------------------

/// Overridden in `main()` with the bootstrapped graph.
///
/// Riverpod is used as a *view* over [AppDependencies], not as the container
/// itself — see the note on that class for why the graph has to exist outside
/// the widget tree.
final Provider<AppDependencies> appDependenciesProvider =
    Provider<AppDependencies>(
      (Ref ref) => throw UnimplementedError(
        'appDependenciesProvider must be overridden in main().',
      ),
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

  /// Called after a successful sign-in. The session manager has already
  /// adopted the session at this point.
  Future<void> onSignedIn() async {
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, false);
    ref.invalidateSelf();
    await _onEnteredApp();
  }

  Future<void> signOut() async {
    await BackgroundScheduler.cancelAll();
    await ref.read(notificationServiceProvider).cancelAll();

    // Riot's login lives in a WebView with its own cookie jar. Clearing our
    // keystore alone would leave that jar intact, and the next sign-in would
    // sail straight past the login page back into the same account.
    await const WebViewCookieReader().clear();
    await ref.read(localStoreProvider).putSetting(SettingKeys.demoMode, false);
    await ref.read(sessionManagerProvider).signOut();

    // Everything user-scoped is now wrong; drop it rather than showing the
    // previous account's shop behind a login screen.
    ref.invalidate(shopControllerProvider);
    ref.invalidate(playerControllerProvider);
    ref.invalidate(ownedSkinsProvider);
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
  Future<Shop> build() {
    // Re-resolve whenever the wishlist changes so the heart on a shop card and
    // the "on your wishlist" banner stay in sync without a manual refresh.
    ref.watch(wishlistControllerProvider);
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
