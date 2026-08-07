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

  /// Last storefront the background worker saw — used to detect a shop reset.
  static const String lastShopSnapshot = 'shop.lastSnapshot';

  /// Locally cached owned-skin UUIDs so the Collection tab renders offline.
  static const String ownedSkinLevels = 'collection.ownedSkinLevels';

  /// Cached player profile (Riot ID / rank / wallet) for the header.
  static const String playerProfile = 'player.profile';
}

abstract final class SettingKeys {
  static const String demoMode = 'demoMode';
  static const String shopNotificationsEnabled = 'notify.shop';
  static const String wishlistNotificationsEnabled = 'notify.wishlist';
  static const String language = 'language';
}
