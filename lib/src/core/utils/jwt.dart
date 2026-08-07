import 'dart:convert';

/// Minimal, signature-*unverified* JWT payload reader.
///
/// We only ever read claims from tokens Riot just handed us over TLS
/// (`exp` on the access token, `affinities.live` on the geo/PAS token), so
/// verification would buy us nothing — but never use this for trust decisions.
abstract final class Jwt {
  static Map<String, dynamic>? decodePayload(String token) {
    final List<String> parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final String normalised = base64Url.normalize(parts[1]);
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(normalised)));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// `exp` claim as a [DateTime], or null when absent/unparseable.
  static DateTime? expiry(String token) {
    final Object? exp = decodePayload(token)?['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
  }

  /// Live affinity (`na`, `eu`, `ap`, `kr`, ...) from Riot's PAS token.
  static String? liveAffinity(String pasToken) {
    final Object? affinities = decodePayload(pasToken)?['affinities'];
    if (affinities is! Map) return null;
    final Object? live = affinities['live'];
    return live is String ? live : null;
  }
}
