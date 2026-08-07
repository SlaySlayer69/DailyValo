/// Static values required to talk to Riot's game-client APIs.
///
/// None of these endpoints are part of Riot's *public* developer API — they are
/// the same endpoints the official desktop client uses. They are stable in
/// practice but undocumented, so every value here is centralised in one place
/// so a breaking change upstream is a one-file fix.
abstract final class RiotConstants {
  // ---------------------------------------------------------------------------
  // Riot Sign On (RSO)
  // ---------------------------------------------------------------------------
  static const String authBase = 'https://auth.riotgames.com';
  static const String authorizationUrl = '$authBase/api/v1/authorization';
  static const String authorizeUrl = '$authBase/authorize';
  static const String userInfoUrl = '$authBase/userinfo';
  static const String entitlementsUrl =
      'https://entitlements.auth.riotgames.com/api/token/v1';
  static const String geoUrl =
      'https://riot-geo.pas.si.riotgames.com/pas/v1/product/valorant';

  static const String clientId = 'play-valorant-web-prod';
  static const String redirectUri = 'https://playvalorant.com/opt_in';
  static const String responseType = 'token id_token';
  static const String scope = 'account openid';
  static const String nonce = '1';

  /// Session cookie handed out by RSO when `remember: true` is sent.
  ///
  /// This is the only credential DailyValo persists — it lets us mint fresh
  /// access tokens without ever keeping the user's password around.
  static const String sessionCookieName = 'ssid';

  /// The auth endpoints reject unknown user agents, so we present the same one
  /// the Riot Client sends.
  static const String userAgent =
      'RiotClient/63.0.9.4909983.4789131 rso-auth (Windows;10;;Professional, x64)';

  /// Base64 of the client platform descriptor the game client sends with every
  /// PD/GLZ request. The decoded payload is:
  /// `{"platformType":"PC","platformOS":"Windows",`
  /// `"platformOSVersion":"10.0.19042.1.256.64bit","platformChipset":"Unknown"}`
  static const String clientPlatform =
      'ew0KCSJwbGF0Zm9ybVR5cGUiOiAiUEMiLA0KCSJwbGF0Zm9ybU9TIjogIldpbmRvd3MiLA0K'
      'CSJwbGF0Zm9ybU9TVmVyc2lvbiI6ICIxMC4wLjE5MDQyLjEuMjU2LjY0Yml0IiwNCgkicGxh'
      'dGZvcm1DaGlwc2V0IjogIlVua25vd24iDQp9';

  /// Fallback used when `valorant-api.com/v1/version` cannot be reached.
  /// The live value is fetched at runtime; this only keeps requests well-formed.
  /// Only used until the live value arrives from valorant-api.com. Keep it
  /// roughly current anyway: some PD endpoints are stricter about this header
  /// than others, and a years-stale value is a plausible cause of a 404 on one
  /// endpoint while the rest answer fine.
  static const String fallbackClientVersion =
      'release-13.02-shipping-10-5229475';

  // ---------------------------------------------------------------------------
  // Player Data (PD) endpoints — `{shard}` is substituted at runtime.
  // ---------------------------------------------------------------------------
  static String pdBase(String shard) => 'https://pd.$shard.a.pvp.net';

  static String storefrontV3(String shard, String puuid) =>
      '${pdBase(shard)}/store/v3/storefront/$puuid';

  static String storefrontV2(String shard, String puuid) =>
      '${pdBase(shard)}/store/v2/storefront/$puuid';

  static String wallet(String shard, String puuid) =>
      '${pdBase(shard)}/store/v1/wallet/$puuid';

  static String entitlementsByType(String shard, String puuid, String typeId) =>
      '${pdBase(shard)}/store/v1/entitlements/$puuid/$typeId';

  /// Full MMR record: seasonal tiers plus the latest competitive update.
  static String mmrPlayer(String shard, String puuid) =>
      '${pdBase(shard)}/mmr/v1/players/$puuid';

  /// Recent rated matches.
  ///
  /// [endIndex] defaults to 20 rather than 1: asking for a single match means
  /// one unrated or placement result at the top of the list hides an otherwise
  /// perfectly good rank.
  static String competitiveUpdates(
    String shard,
    String puuid, {
    int endIndex = 20,
    String? queue = 'competitive',
  }) =>
      '${pdBase(shard)}/mmr/v1/players/$puuid/competitiveupdates'
      '?startIndex=0&endIndex=$endIndex'
      '${queue == null ? '' : '&queue=$queue'}';

  // ---------------------------------------------------------------------------
  // Well-known UUIDs
  // ---------------------------------------------------------------------------

  /// Wallet currency identifiers.
  static const String currencyValorantPoints =
      '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  // Verified against valorant-api.com/v1/currencies. Getting this wrong is
  // silent: the wallet endpoint simply has no such key, so the balance reads
  // as a plausible 0 rather than failing.
  static const String currencyRadianitePoints =
      'e59aa87c-4cbf-517a-5983-6e81511be9b7';
  static const String currencyKingdomCredits =
      '85ca954a-41f2-ce94-9b45-8ca3dd39a00d';

  /// Entitlement (owned item) categories.
  static const String itemTypeSkinLevels =
      'e7c63390-eda7-46e0-bb7a-a6abdacd2433';
  static const String itemTypeSkinChromas =
      '3ad1b2b2-acdb-4524-852f-954a76ddae0a';

  // ---------------------------------------------------------------------------
  // Region → shard routing
  // ---------------------------------------------------------------------------
  static const Map<String, String> regionToShard = <String, String>{
    'na': 'na',
    'latam': 'na',
    'br': 'na',
    'eu': 'eu',
    'ap': 'ap',
    'kr': 'kr',
    'pbe': 'pbe',
  };

  static String shardForRegion(String region) =>
      regionToShard[region.toLowerCase()] ?? 'na';
}
