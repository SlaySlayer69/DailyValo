/// Strips credentials out of anything on its way into the log file.
///
/// This is not defence in depth, it is the only defence. The log exists to be
/// **exported** — sent to a chat, attached to an issue, handed to someone who
/// is helping — and everything this app talks to is authenticated with bearer
/// tokens that are as good as the password until they expire. The `ssid` cookie
/// is worse: it does not expire in an hour, and it mints new tokens on demand.
///
/// Applied at the sink rather than at each call site, because a call site that
/// forgets is exactly how a token ends up in a file someone posts publicly.
/// Nothing reaches the file without passing through here.
abstract final class LogRedaction {
  /// JWTs, which every Riot token is: three base64url segments split by dots.
  /// Matched on shape rather than on the name of the field carrying it, so a
  /// token logged as part of an unexpected payload is caught too.
  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\b',
  );

  /// `Authorization: Bearer <anything>` even when the value is not a JWT.
  static final RegExp _bearer = RegExp(
    r'(?<=[Bb]earer )[A-Za-z0-9._~+/=-]{8,}',
  );

  /// Named secrets in JSON or query strings: `"accessToken":"…"`, `ssid=…`.
  static final RegExp _named = RegExp(
    r'''(?<key>ssid|access_?token|id_?token|entitlements?_?token|refresh_?token|password|clid|asid|tdid|sub)'''
    r'''(?<sep>"?\s*[:=]\s*"?)(?<value>[^"&,;}\s]{4,})''',
    caseSensitive: false,
  );

  /// What a redacted value is replaced with. Deliberately keeps the length out
  /// of it — "how long was the token" is not worth leaking and not worth
  /// debugging with.
  static const String mask = '«redacted»';

  /// Runs every rule. Order matters only in that the named rule would otherwise
  /// re-mask an already-masked value, which is harmless but noisy.
  static String apply(String line) {
    return line
        .replaceAll(_jwt, mask)
        .replaceAll(_bearer, mask)
        .replaceAllMapped(
          _named,
          (Match m) {
            final RegExpMatch match = m as RegExpMatch;
            return '${match.namedGroup('key')}'
                '${match.namedGroup('sep')}$mask';
          },
        );
  }
}
