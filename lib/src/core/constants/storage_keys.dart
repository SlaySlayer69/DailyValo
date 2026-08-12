/// Keys used for encrypted (secure) storage and for Hive boxes.
///
/// Kept in one file so the background isolate and the UI isolate can never
/// drift apart on a key name.
abstract final class SecureKeys {
  /// Serialised [RiotSession] (tokens + puuid + routing).
  static const String session = 'dv.session';

  /// The long-lived RSO `ssid` cookie used to mint new access tokens.
  static const String sessionCookie = 'dv.ssid';
}

abstract final class HiveBoxes {
  /// Wishlist entries, keyed by skin UUID. Values are JSON strings.
  static const String wishlist = 'dv_wishlist';

  /// Cached `valorant-api.com` catalogue + misc. app state. JSON strings.
  static const String cache = 'dv_cache';

  /// Small scalar preferences (demo mode, notification toggles, ...).
  static const String settings = 'dv_settings';
}

abstract final class CacheKeys {
  static const String contentCatalog = 'content.catalog';
  static const String contentCatalogVersion = 'content.catalog.version';
  static const String contentCatalogFetchedAt = 'content.catalog.fetchedAt';
  static const String clientVersion = 'riot.clientVersion';

  /// UUID of the act currently running — the key the MMR record is indexed by.
  static const String currentActUuid = 'content.currentAct';
  static const String currentActFetchedAt = 'content.currentAct.fetchedAt';

  /// Most recent storefront, kept so the shop renders offline and instantly on
  /// launch. Written by *any* fetch, including one the user triggered by
  /// opening the tab.
  static const String lastShopSnapshot = 'shop.lastSnapshot';

  /// The offer ids the user has already been told about.
  ///
  /// Deliberately separate from [lastShopSnapshot], which cannot answer this
  /// question: the shop cache is overwritten by every fetch, including the one
  /// the Daily Shop tab makes when you open the app. Using it as the "have I
  /// mentioned these?" baseline meant opening the app shortly after a rotation
  /// wrote the new offers into the baseline *before* anything compared against
  /// it — so the rotation was silently consumed and the notification for it
  /// could never fire. Only [ShopSyncService] writes this one.
  static const String lastNotifiedOfferIds = 'shop.lastNotifiedOfferIds';

  /// Locally cached owned-skin UUIDs so the Collection tab renders offline.
  static const String ownedSkinLevels = 'collection.ownedSkinLevels';

  /// What the background worker last did, and how many times it has run.
  ///
  /// Survives a sign-out on purpose — it is about Android's willingness to
  /// start the task, not about the account, and wiping it would destroy the
  /// evidence exactly when someone is debugging.
  static const String lastBackgroundRun = 'background.lastRun';

  /// Cached player profile (Riot ID / rank / wallet) for the header.
  static const String playerProfile = 'player.profile';
}

abstract final class SettingKeys {
  static const String demoMode = 'demoMode';
  static const String shopNotificationsEnabled = 'notify.shop';
  static const String wishlistNotificationsEnabled = 'notify.wishlist';

  /// Hold notifications back to a chosen time of day instead of firing them
  /// as soon as the shop rotation is noticed.
  static const String notifyAtFixedTime = 'notify.atFixedTime';

  /// Minutes since local midnight — see [NotificationSchedule].
  static const String notifyTimeOfDay = 'notify.timeOfDay';

  static const String language = 'language';

  /// Reveals the developer tools — diagnostics, the notification test and the
  /// log. Off by default: they answer questions most people never ask, and a
  /// settings screen that leads with debugging is a worse settings screen.
  static const String developerMode = 'dev.enabled';

  /// Writes a detailed log to a file that can be exported.
  ///
  /// Read by both isolates, which is why it lives here rather than in memory:
  /// the background worker has no way to ask the UI whether logging is on, and
  /// the worker is the part most worth logging.
  static const String verboseLogging = 'dev.logging';
}
