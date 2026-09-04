/// Keys used for encrypted (secure) storage and for Hive boxes.
///
/// Kept in one file so the background isolate and the UI isolate can never
/// drift apart on a key name.
abstract final class SecureKeys {
  /// Serialised [RiotSession] (tokens + puuid + routing), single-account era.
  ///
  /// Kept only so the migration to per-account storage can find it. Nothing
  /// reads or writes it any more.
  static const String legacySession = 'dv.session';

  /// The long-lived RSO `ssid` cookie, single-account era. See above.
  static const String legacySessionCookie = 'dv.ssid';

  static String session(String accountId) => 'dv.session.$accountId';

  static String sessionCookie(String accountId) => 'dv.ssid.$accountId';
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

  // --- Per account ----------------------------------------------------------
  //
  // Everything below is scoped by puuid. The unsuffixed names are the
  // single-account layout and survive only so the migration can find and move
  // them; nothing reads them after that.

  static const String legacyShopSnapshot = 'shop.lastSnapshot';
  static const String legacyNotifiedOfferIds = 'shop.lastNotifiedOfferIds';
  static const String legacyOwnedSkinLevels = 'collection.ownedSkinLevels';
  static const String legacyPlayerProfile = 'player.profile';

  /// Most recent storefront, kept so the shop renders offline and instantly on
  /// launch. Written by *any* fetch, including one the user triggered by
  /// opening the tab.
  static String shopSnapshot(String accountId) =>
      'shop.lastSnapshot.$accountId';

  /// The offer ids the user has already been told about.
  ///
  /// Deliberately separate from [lastShopSnapshot], which cannot answer this
  /// question: the shop cache is overwritten by every fetch, including the one
  /// the Daily Shop tab makes when you open the app. Using it as the "have I
  /// mentioned these?" baseline meant opening the app shortly after a rotation
  /// wrote the new offers into the baseline *before* anything compared against
  /// it — so the rotation was silently consumed and the notification for it
  /// could never fire. Only [ShopSyncService] writes this one.
  static String notifiedOfferIds(String accountId) =>
      'shop.lastNotifiedOfferIds.$accountId';

  /// Locally cached owned-skin UUIDs so the Collection tab renders offline.
  static String ownedSkinLevels(String accountId) =>
      'collection.ownedSkinLevels.$accountId';

  /// Owned sprays, buddies, player cards and titles.
  ///
  /// Separate from the skins: they come from four different entitlement calls,
  /// they refresh on a different cadence, and one being missing must not make
  /// the other look empty.
  static String ownedAccessories(String accountId) =>
      'collection.ownedAccessories.$accountId';

  /// When each skin was last offered in this account's daily shop.
  ///
  /// Riot has no history endpoint — the storefront is only ever a snapshot of
  /// now — so "how long have I been waiting for this?" is answerable only if
  /// the app writes it down as each shop goes past.
  static String shopSightings(String accountId) =>
      'shop.sightings.$accountId';

  /// Whether a Night Market was running the last time this account's shop was
  /// read, so its *arrival* can be noticed rather than just its presence.
  static String nightMarketSeen(String accountId) =>
      'shop.nightMarketSeen.$accountId';

  /// What the background worker last did, and how many times it has run.
  ///
  /// Survives a sign-out on purpose — it is about Android's willingness to
  /// start the task, not about the account, and wiping it would destroy the
  /// evidence exactly when someone is debugging.
  static const String lastBackgroundRun = 'background.lastRun';

  /// Cached player profile (Riot ID / rank / wallet) for the header.
  static String playerProfile(String accountId) => 'player.profile.$accountId';

  // --- Device-wide ----------------------------------------------------------

  /// The signed-in accounts, and which one the UI is showing.
  static const String accounts = 'accounts.list';
  static const String activeAccount = 'accounts.active';

  /// Set once the single-account layout has been moved to per-account keys.
  static const String accountMigrationDone = 'accounts.migrated';
}

abstract final class SettingKeys {
  static const String demoMode = 'demoMode';
  static const String shopNotificationsEnabled = 'notify.shop';
  static const String wishlistNotificationsEnabled = 'notify.wishlist';

  /// Tells you when a Night Market opens. On its own switch because it fires a
  /// few times a year rather than daily — the one people are most likely to
  /// want, and the one most likely to be forgotten about.
  static const String nightMarketNotificationsEnabled = 'notify.nightMarket';

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
