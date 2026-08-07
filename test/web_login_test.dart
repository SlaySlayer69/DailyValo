import 'package:dailyvalo/src/core/network/webview_cookie_reader.dart';
import 'package:dailyvalo/src/features/auth/presentation/pages/riot_login_webview_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the two pieces of the WebView sign-in that would fail silently and
/// unreproducibly if they were wrong: reading the session cookie out of the
/// native jar, and recognising Riot's final redirect.
void main() {
  group('Cookie header parsing', () {
    test('splits each pair on the first "=" only', () {
      // Opaque session tokens routinely contain "=" (base64 padding). Splitting
      // on every occurrence truncates them, which would log the user in once
      // and then break every background refresh.
      const String header = 'ssid=abc.def==; tdid=xyz; clid=eu1';
      final Map<String, String> cookies =
          WebViewCookieReader.parseCookieHeader(header);

      expect(cookies['ssid'], 'abc.def==');
      expect(cookies['tdid'], 'xyz');
      expect(cookies['clid'], 'eu1');
    });

    test('tolerates the whitespace variations Android emits', () {
      final Map<String, String> cookies =
          WebViewCookieReader.parseCookieHeader('  ssid=a1 ;tdid=b2;  ');

      expect(cookies['ssid'], 'a1');
      expect(cookies['tdid'], 'b2');
      expect(cookies, hasLength(2));
    });

    test('returns empty for null, blank or valueless input', () {
      expect(WebViewCookieReader.parseCookieHeader(null), isEmpty);
      expect(WebViewCookieReader.parseCookieHeader(''), isEmpty);
      expect(WebViewCookieReader.parseCookieHeader('   '), isEmpty);
      // A bare flag carries nothing we can replay.
      expect(WebViewCookieReader.parseCookieHeader('secure'), isEmpty);
      expect(WebViewCookieReader.parseCookieHeader('=novalue'), isEmpty);
    });

    test('keeps a JWT-shaped value intact', () {
      const String jwt =
          'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl==';
      final Map<String, String> cookies =
          WebViewCookieReader.parseCookieHeader('ssid=$jwt');

      expect(cookies['ssid'], jwt);
    });
  });

  group('Riot redirect detection', () {
    const String redirect = 'https://playvalorant.com/opt_in';

    test('ignores every page of the login flow itself', () {
      expect(RiotRedirectResult.tryParse('https://auth.riotgames.com/login'), isNull);
      expect(
        RiotRedirectResult.tryParse(
          'https://auth.riotgames.com/authorize?client_id=play-valorant-web-prod',
        ),
        isNull,
      );
      // The redirect host without a fragment is not yet the payload.
      expect(RiotRedirectResult.tryParse(redirect), isNull);
    });

    test('extracts tokens from the success fragment', () {
      final RiotRedirectResult? result = RiotRedirectResult.tryParse(
        '$redirect#access_token=AT123&scope=account%20openid'
        '&id_token=ID456&token_type=Bearer&expires_in=3600',
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.tokens!.accessToken, 'AT123');
      expect(result.tokens!.idToken, 'ID456');
      expect(result.tokens!.expiresIn, 3600);
    });

    test('defaults expiry when Riot omits expires_in', () {
      final RiotRedirectResult result = RiotRedirectResult.tryParse(
        '$redirect#access_token=AT&id_token=ID',
      )!;

      expect(result.tokens!.expiresIn, 3600);
    });

    test('reports a rejection rather than pretending it is still loading', () {
      final RiotRedirectResult result = RiotRedirectResult.tryParse(
        '$redirect#error=access_denied',
      )!;

      expect(result.isSuccess, isFalse);
      expect(result.error, 'access_denied');
      expect(result.tokens, isNull);
    });

    test('treats an empty access token as a rejection', () {
      final RiotRedirectResult result = RiotRedirectResult.tryParse(
        '$redirect#access_token=&id_token=ID',
      )!;

      expect(result.isSuccess, isFalse);
      expect(result.error, 'unknown');
    });
  });
}
