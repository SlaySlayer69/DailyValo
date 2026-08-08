import 'package:timezone/timezone.dart' as tz;

import '../../app/dependencies.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/utils/logger.dart';
import '../../features/content/data/models/content_catalog.dart';
import '../../features/content/data/models/weapon_skin.dart';
import '../../features/store/data/models/shop.dart';
import '../../features/store/data/models/storefront_snapshot.dart';
import '../../features/wishlist/data/models/wishlist_entry.dart';
import '../notifications/notification_schedule.dart';

/// What a sync did, so the caller (and the tests) can tell.
class ShopSyncOutcome {
  const ShopSyncOutcome({
    required this.shopChanged,
    required this.wishlistMatches,
    required this.nextResetAt,
    this.skipped,
    this.notificationsDeferredUntil,
  });

  /// The four offers differ from the ones we last saw.
  final bool shopChanged;

  final List<WishlistEntry> wishlistMatches;

  /// When the shop rotates next — used to schedule the follow-up check.
  final DateTime? nextResetAt;

  /// Non-null when nothing was done, with the reason.
  final String? skipped;

  /// Set when the user chose a delivery time and the notifications were handed
  /// to Android for later rather than posted now.
  final DateTime? notificationsDeferredUntil;

  bool get didWork => skipped == null;

  static ShopSyncOutcome skip(String reason) =>
      ShopSyncOutcome(
        shopChanged: false,
        wishlistMatches: const <WishlistEntry>[],
        nextResetAt: null,
        skipped: reason,
      );
}

/// Detects a shop reset and fires the two notifications.
///
/// Runs identically in the foreground (on app resume) and in the WorkManager
/// isolate — that symmetry is why "did the shop change?" is decided by
/// comparing persisted offer ids rather than by trusting a wall clock. The
/// device can be asleep past reset, the timezone can change, the worker can be
/// deferred by Doze for hours; the offer set is the only honest signal.
class ShopSyncService {
  ShopSyncService(this._deps);

  final AppDependencies _deps;

  Future<ShopSyncOutcome> sync() async {
    if (!_deps.canFetchShop) return ShopSyncOutcome.skip('not signed in');

    final StorefrontSnapshot? previous = _deps.store.cachedSnapshot;

    // `forceRefresh` bypasses the "cached and not expired" shortcut. The worker
    // is only ever woken when something might have changed, so paying for the
    // round trip is the point.
    final Shop shop = await _deps.store.getShop(forceRefresh: true);
    final Set<String> currentIds = shop.dailyOffers
        .map((ShopOffer o) => o.offerId)
        .toSet();

    // First run has no baseline. Record it silently rather than announcing a
    // "new" shop the user has been looking at all day.
    if (previous == null) {
      Log.d('Sync', 'No baseline snapshot; recording without notifying');
      return ShopSyncOutcome(
        shopChanged: false,
        wishlistMatches: const <WishlistEntry>[],
        nextResetAt: shop.dailyResetAt,
      );
    }

    final bool changed = !_sameOffers(previous.dailyOfferIds, currentIds);
    if (!changed) {
      Log.d('Sync', 'Shop unchanged');
      return ShopSyncOutcome(
        shopChanged: false,
        wishlistMatches: const <WishlistEntry>[],
        nextResetAt: shop.dailyResetAt,
      );
    }

    Log.d('Sync', 'Shop rotated — ${currentIds.length} new offers');

    // The wishlist alert is a *separate* notification on a *separate* channel,
    // fired only when there is a match — so a normal reset never buzzes.
    final List<WishlistEntry> matches = _deps.wishlist.matching(currentIds);

    final DateTime? deferredUntil = await _notify(shop, matches);

    return ShopSyncOutcome(
      shopChanged: true,
      wishlistMatches: matches,
      nextResetAt: shop.dailyResetAt,
      notificationsDeferredUntil: deferredUntil,
    );
  }

  /// Posts both notifications, now or at the user's chosen time.
  ///
  /// Returns the delivery time when it was deferred, null when posted straight
  /// away. Detection is unaffected either way — only the delivery moves, and
  /// the shop cannot change again between reset and the chosen hour, so a held
  /// notification is still accurate when it lands.
  Future<DateTime?> _notify(Shop shop, List<WishlistEntry> matches) async {
    final NotificationSchedule schedule = NotificationSchedule.read(
      _deps.localStore,
    );

    final bool wantsShop = _deps.localStore.setting<bool>(
      SettingKeys.shopNotificationsEnabled,
      true,
    );
    final bool wantsWishlist =
        matches.isNotEmpty &&
        _deps.localStore.setting<bool>(
          SettingKeys.wishlistNotificationsEnabled,
          true,
        );

    final List<String> matchLabels = matches
        .map((WishlistEntry e) => e.label)
        .toList(growable: false);

    if (!schedule.enabled) {
      if (wantsShop) await _deps.notifications.showDailyShop(_labelsFor(shop));
      if (wantsWishlist) {
        await _deps.notifications.showWishlistHit(matchedLabels: matchLabels);
      }
      return null;
    }

    // In the device's own zone, so "09:00" survives a clock change.
    final tz.TZDateTime at = schedule.nextDeliveryAfter(
      tz.TZDateTime.now(tz.local),
    );

    // A second rotation before the first was delivered replaces it, rather
    // than leaving yesterday's digest queued behind today's.
    await _deps.notifications.cancelScheduled();

    if (wantsShop) {
      await _deps.notifications.scheduleDailyShop(_labelsFor(shop), at);
    }
    if (wantsWishlist) {
      await _deps.notifications.scheduleWishlistHit(
        at: at,
        matchedLabels: matchLabels,
      );
    }
    Log.d('Sync', 'Notifications deferred to $at');
    return at;
  }

  /// `Vandal: Prime` for each offer, in shop order.
  ///
  /// Falls back to the raw catalogue lookup when an offer could not be resolved
  /// into a full [ShopOffer]; if even that fails the entry is dropped rather
  /// than shipping a UUID to the notification shade.
  List<String> _labelsFor(Shop shop) {
    if (shop.dailyOffers.isNotEmpty) {
      return shop.dailyOffers
          .map((ShopOffer o) => o.skin.notificationLabel)
          .toList(growable: false);
    }

    final ContentCatalog? catalog = _deps.content.cached;
    final StorefrontSnapshot? snapshot = _deps.store.cachedSnapshot;
    if (catalog == null || snapshot == null) return const <String>[];

    return snapshot.dailyOffers
        .map((RawOffer o) => catalog.skinByOfferUuid(o.offerId))
        .whereType<WeaponSkin>()
        .map((WeaponSkin s) => s.notificationLabel)
        .toList(growable: false);
  }

  static bool _sameOffers(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
