import 'package:dailyvalo/src/core/constants/riot_constants.dart';
import 'package:dailyvalo/src/features/auth/data/datasources/riot_auth_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The silent re-auth request, pinned header by header.
///
/// This one call is every session renewal in the app: the background worker
/// uses it, and so does the cold-start recovery that keeps the login screen
/// away. It got an **HTTP 406** from Riot for its entire life, because the auth
/// client sets `Accept: application/json` on every request — correct for the
/// JSON endpoints it was built for, and wrong for `/authorize`, which is a
/// browser endpoint that answers with a 303 and a `Location` header.
///
/// The consequences were nothing like the size of the cause. Every renewal
/// failed; the failure was read as "the cookie is dead"; the app signed itself
/// out about an hour after each sign-in; and a signed-out background worker
/// skips every run, so no shop rotation was ever detected and no notification
/// was ever scheduled. From outside it looked like a login button that signed
/// you straight back in without asking for anything, and a digest that never
/// arrived.
///
/// Verified against the live endpoint when this was written: with
/// `Accept: application/json` it answers 406; with `*/*`, no Accept, or a
/// browser Accept it answers 303. Both `+` and `%20` in `response_type` are
/// fine, which ruled the encoding out.
void main() {
  group('Silent re-auth request', () {
    test('does not ask /authorize for JSON', () {
      final Options options = RiotAuthApi.authorizeOptions('cookie-value');
      final Object? accept = options.headers?['Accept'];

      expect(accept, isNotNull, reason: 'Accept must be overridden explicitly');
      expect(
        accept,
        isNot(contains('application/json')),
        reason: 'application/json here is an HTTP 406 from Riot',
      );
    });

    test('sends the session cookie, and only that cookie', () {
      final Options options = RiotAuthApi.authorizeOptions('abc123');
      expect(
        options.headers?['Cookie'],
        '${RiotConstants.sessionCookieName}=abc123',
      );
    });

    test('does not follow the redirect it is there to read', () {
      // The tokens arrive in the Location header's fragment. Following it
      // throws that away and lands on playvalorant.com.
      expect(RiotAuthApi.authorizeOptions('x').followRedirects, isFalse);
    });

    test('treats a 3xx as a response rather than an error', () {
      final bool Function(int?)? validate =
          RiotAuthApi.authorizeOptions('x').validateStatus;
      expect(validate, isNotNull);
      expect(validate!(303), isTrue);
      expect(validate(302), isTrue);
      // A server error still has to throw, so it is retried rather than read
      // as a dead cookie.
      expect(validate(500), isFalse);
    });

    test('carries every parameter Riot requires', () {
      final Uri uri = RiotAuthApi.authorizeUri();
      expect(uri.host, 'auth.riotgames.com');
      expect(uri.path, '/authorize');
      expect(uri.queryParameters, <String, String>{
        'redirect_uri': RiotConstants.redirectUri,
        'client_id': RiotConstants.clientId,
        'response_type': RiotConstants.responseType,
        'nonce': RiotConstants.nonce,
        'scope': RiotConstants.scope,
      });
    });

    test('asks for both tokens in one round trip', () {
      final Uri uri = RiotAuthApi.authorizeUri();
      expect(uri.queryParameters['response_type'], contains('token'));
      expect(uri.queryParameters['response_type'], contains('id_token'));
      expect(uri.queryParameters['scope'], contains('openid'));
    });
  });
}
