import 'package:dailyvalo/src/services/logging/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// The log is built to be **exported** — sent to a chat, attached to an issue,
/// handed to whoever is helping. Everything this app talks to is authenticated
/// with bearer tokens that are as good as the password until they expire, and
/// the `ssid` cookie is worse: it does not expire in an hour and it mints new
/// tokens on demand.
///
/// So these are not style tests. A regression here writes a working credential
/// into a file someone posts publicly.
void main() {
  const String jwt =
      'eyJhbGciOiJSUzI1NiIsImtpZCI6InMx.eyJzdWIiOiJhYmMxMjMiLCJleHAiOjE3MH.'
      'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

  group('LogRedaction', () {
    test('removes a JWT wherever it appears', () {
      final String out = LogRedaction.apply('Authorization: Bearer $jwt');
      expect(out, isNot(contains(jwt)));
      expect(out, contains(LogRedaction.mask));
    });

    test('removes a JWT that is not labelled as a token at all', () {
      // Matched on shape, not on the field carrying it — a token that turns up
      // in an unexpected payload is still a token.
      final String out = LogRedaction.apply('{"unexpected":"$jwt"}');
      expect(out, isNot(contains(jwt)));
    });

    test('removes a bearer value that is not a JWT', () {
      final String out = LogRedaction.apply(
        'authorization: Bearer abcdef0123456789-opaque_token',
      );
      expect(out, isNot(contains('abcdef0123456789')));
    });

    test('removes the ssid cookie in a header', () {
      const String cookie = 'ssid=r4nd0m0paqueC00kieValue123456';
      final String out = LogRedaction.apply('Cookie: $cookie; tdid=x');
      expect(out, isNot(contains('r4nd0m0paqueC00kieValue123456')));
    });

    test('removes named secrets in JSON', () {
      final String out = LogRedaction.apply(
        '{"accessToken":"aaaabbbbcccc","idToken":"ddddeeeeffff",'
        '"entitlements_token":"gggghhhhiiii"}',
      );
      for (final String secret in <String>[
        'aaaabbbbcccc',
        'ddddeeeeffff',
        'gggghhhhiiii',
      ]) {
        expect(out, isNot(contains(secret)), reason: '$secret survived');
      }
    });

    test('removes tokens from a redirect URL fragment', () {
      // This is exactly how sign-in completes, and the whole URL used to be
      // logged as "the request that came back".
      final String out = LogRedaction.apply(
        'https://playvalorant.com/opt_in#access_token=$jwt'
        '&id_token=$jwt&expires_in=3600',
      );
      expect(out, isNot(contains(jwt)));
      // The shape of the redirect is what makes the log useful; only the values
      // go.
      expect(out, contains('playvalorant.com/opt_in'));
      expect(out, contains('expires_in=3600'));
    });

    test('does not mask the length of what it removed', () {
      final String short = LogRedaction.apply('access_token=abcd1234');
      final String long = LogRedaction.apply('access_token=${'x' * 400}');
      expect(short.length, long.length);
    });

    test('leaves ordinary log lines untouched', () {
      // Over-redaction makes the log useless, which is its own failure.
      const String line =
          '09:15:02.114 D [bg] Worker: Task fired: shopResetCheck';
      expect(LogRedaction.apply(line), line);
    });

    test('keeps the parts of a request that make it worth logging', () {
      const String line =
          '→ GET https://pd.eu.a.pvp.net/store/v3/storefront/abc-123 (204ms)';
      expect(LogRedaction.apply(line), line);
    });

    test('is idempotent, so a re-logged line does not decay', () {
      final String once = LogRedaction.apply('access_token=abcd1234');
      expect(LogRedaction.apply(once), once);
    });
  });
}
