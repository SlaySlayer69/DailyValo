/// Endpoints for `valorant-api.com` — a free, unauthenticated community mirror
/// of the game's static content (names, artwork, tiers, chromas).
///
/// Everything Riot's storefront returns is a bare UUID; this is what turns those
/// UUIDs into something a human can look at.
abstract final class ValorantApiConstants {
  static const String base = 'https://valorant-api.com/v1';

  /// Language tag sent to the content API. Riot's own locale format, e.g.
  /// `en-US`, `de-DE`, `ja-JP`.
  static const String defaultLanguage = 'en-US';

  static const String weapons = '$base/weapons';
  static const String weaponSkins = '$base/weapons/skins';
  static const String contentTiers = '$base/contenttiers';
  static const String competitiveTiers = '$base/competitivetiers';
  static const String bundles = '$base/bundles';

  /// Acts and episodes. Used to find the act the MMR record is keyed by.
  static const String seasons = '$base/seasons';
  static const String version = '$base/version';

  /// Currency icons served from the same CDN, addressed by currency UUID.
  static String currencyIcon(String currencyUuid) =>
      'https://media.valorant-api.com/currencies/$currencyUuid/displayicon.png';
}
