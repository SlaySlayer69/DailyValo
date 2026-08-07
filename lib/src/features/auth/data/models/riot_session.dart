import '../../../../core/constants/riot_constants.dart';
import '../../../../core/utils/jwt.dart';

/// An authenticated Riot session: the three tokens every PD request needs,
/// plus the routing and identity we derived once at sign-in.
///
/// Persisted (encrypted) so a cold start does not force a re-login, and read
/// verbatim by the background isolate.
class RiotSession {
  const RiotSession({
    required this.accessToken,
    required this.idToken,
    required this.entitlementsToken,
    required this.puuid,
    required this.gameName,
    required this.tagLine,
    required this.region,
    required this.shard,
    required this.expiresAt,
  });

  /// RSO bearer token. Short-lived (~1h).
  final String accessToken;

  /// Needed by the geo/PAS endpoint when re-resolving the player's region.
  final String idToken;

  /// `X-Riot-Entitlements-JWT`. Minted from the access token; expires with it.
  final String entitlementsToken;

  final String puuid;
  final String gameName;
  final String tagLine;

  /// Live affinity, e.g. `eu`. Drives GLZ routing.
  final String region;

  /// PD shard the affinity maps onto, e.g. `eu`.
  final String shard;

  final DateTime expiresAt;

  String get riotId => tagLine.isEmpty ? gameName : '$gameName#$tagLine';

  /// Treat the session as stale a minute early so a request never races the
  /// expiry while it is in flight.
  bool get isExpired =>
      DateTime.now().toUtc().isAfter(
        expiresAt.subtract(const Duration(minutes: 1)),
      );

  RiotSession copyWith({
    String? accessToken,
    String? idToken,
    String? entitlementsToken,
    DateTime? expiresAt,
  }) {
    return RiotSession(
      accessToken: accessToken ?? this.accessToken,
      idToken: idToken ?? this.idToken,
      entitlementsToken: entitlementsToken ?? this.entitlementsToken,
      puuid: puuid,
      gameName: gameName,
      tagLine: tagLine,
      region: region,
      shard: shard,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Builds a session from a freshly minted token set.
  ///
  /// [expiresAt] prefers the access token's own `exp` claim and falls back to
  /// the `expires_in` value from the redirect fragment.
  factory RiotSession.fromTokens({
    required String accessToken,
    required String idToken,
    required String entitlementsToken,
    required String puuid,
    required String gameName,
    required String tagLine,
    required String region,
    required int expiresInSeconds,
  }) {
    return RiotSession(
      accessToken: accessToken,
      idToken: idToken,
      entitlementsToken: entitlementsToken,
      puuid: puuid,
      gameName: gameName,
      tagLine: tagLine,
      region: region,
      shard: RiotConstants.shardForRegion(region),
      expiresAt:
          Jwt.expiry(accessToken) ??
          DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'accessToken': accessToken,
    'idToken': idToken,
    'entitlementsToken': entitlementsToken,
    'puuid': puuid,
    'gameName': gameName,
    'tagLine': tagLine,
    'region': region,
    'shard': shard,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory RiotSession.fromJson(Map<String, dynamic> json) {
    final String region = (json['region'] as String?) ?? 'na';
    return RiotSession(
      accessToken: json['accessToken'] as String? ?? '',
      idToken: json['idToken'] as String? ?? '',
      entitlementsToken: json['entitlementsToken'] as String? ?? '',
      puuid: json['puuid'] as String? ?? '',
      gameName: json['gameName'] as String? ?? '',
      tagLine: json['tagLine'] as String? ?? '',
      region: region,
      shard:
          json['shard'] as String? ?? RiotConstants.shardForRegion(region),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
