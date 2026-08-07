import 'package:dio/dio.dart';

import '../../../../core/constants/riot_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_factory.dart';
import '../../../../core/storage/secure_token_store.dart';
import '../../../../core/utils/jwt.dart';
import '../../../../core/utils/logger.dart';
import '../models/riot_session.dart';

/// Riot Sign On + Entitlements, end to end.
///
/// Sign-in happens in a WebView on Riot's own hosted login page; this class
/// picks up where that leaves off. The direct username/password endpoint used
/// to live here and was removed, because it cannot complete a sign-in for any
/// account Riot protects with push confirmation or a captcha — it answers
/// `auth_failure` even when the password is correct, which is indistinguishable
/// from a typo and impossible to act on.
///
/// What remains:
///
/// ```
///  (WebView) GET /authorize          -> user signs in, redirect carries tokens
///  POST /api/token/v1  (entitlements)-> X-Riot-Entitlements-JWT
///  POST /userinfo                    -> puuid + Riot ID
///  PUT  /pas/v1/product/valorant     -> PAS token, carries the live affinity
/// ```
///
/// Later refreshes skip the WebView entirely: the `ssid` cookie captured from
/// its jar is replayed against `GET /authorize`, which 303s back with a fresh
/// token pair. That is what lets the *background isolate* refresh tokens — a
/// WebView needs an Activity and cannot run from WorkManager.
class RiotAuthApi {
  RiotAuthApi({required SecureTokenStore secureStore})
    : _secureStore = secureStore;

  final SecureTokenStore _secureStore;

  // ---------------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------------

  /// Finishes a WebView sign-in.
  ///
  /// [ssidCookie] is the session cookie lifted from the WebView's jar. Without
  /// it the session still works until the access token lapses in about an
  /// hour, after which the user has to sign in again — so a missing cookie is
  /// logged loudly rather than passed over.
  Future<RiotSession> completeWebLogin({
    required String accessToken,
    required String idToken,
    required int expiresInSeconds,
    String? ssidCookie,
  }) async {
    if (ssidCookie != null && ssidCookie.isNotEmpty) {
      await _secureStore.writeSessionCookie(ssidCookie);
    } else {
      Log.e(
        'Auth',
        'No ssid cookie captured — background refresh will not work and the '
            'session will end when the access token expires',
      );
    }

    return _buildSession(
      _TokenPair(
        accessToken: accessToken,
        idToken: idToken,
        expiresIn: expiresInSeconds,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Re-authentication (silent refresh)
  // ---------------------------------------------------------------------------

  /// Mints a fresh token set for an existing session using the stored cookie.
  ///
  /// Throws an [AuthException] with `requiresReLogin` when the cookie itself
  /// has been revoked or aged out, which is the signal to send the user back to
  /// the login screen.
  Future<RiotSession> reauthenticate(RiotSession current) async {
    final String? ssid = await _secureStore.readSessionCookie();
    if (ssid == null || ssid.isEmpty) {
      throw const AuthException(
        'Your saved Riot session is gone. Please sign in again.',
        requiresReLogin: true,
      );
    }

    final Dio dio = DioFactory.createAuthClient();
    final Uri authorize = Uri.parse(RiotConstants.authorizeUrl).replace(
      queryParameters: <String, String>{
        'redirect_uri': RiotConstants.redirectUri,
        'client_id': RiotConstants.clientId,
        'response_type': RiotConstants.responseType,
        'nonce': RiotConstants.nonce,
        'scope': RiotConstants.scope,
      },
    );

    final Response<dynamic> response = await dio.getUri<dynamic>(
      authorize,
      options: Options(
        followRedirects: false,
        headers: <String, String>{
          'Cookie': '${RiotConstants.sessionCookieName}=$ssid',
        },
        validateStatus: (int? status) => status != null && status < 500,
      ),
    );

    final String location = response.headers.value('location') ?? '';
    if (!location.contains('access_token=')) {
      Log.d('Auth', 'Re-auth rejected; redirect went to ${_origin(location)}');
      throw const AuthException(
        'Your Riot session expired. Please sign in again.',
        requiresReLogin: true,
      );
    }

    // Riot rotates the cookie on every re-auth; keep the newest one.
    final String? rotated = _ssidFromSetCookie(response.headers);
    if (rotated != null) await _secureStore.writeSessionCookie(rotated);

    final _TokenPair tokens = _parseRedirect(location);
    final String entitlements = await _fetchEntitlementsToken(
      tokens.accessToken,
    );

    return current.copyWith(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
      entitlementsToken: entitlements,
      expiresAt:
          Jwt.expiry(tokens.accessToken) ??
          DateTime.now().toUtc().add(Duration(seconds: tokens.expiresIn)),
    );
  }

  // ---------------------------------------------------------------------------
  // Post-token bootstrap
  // ---------------------------------------------------------------------------

  Future<RiotSession> _buildSession(_TokenPair tokens) async {
    final String entitlements = await _fetchEntitlementsToken(
      tokens.accessToken,
    );
    final _UserInfo user = await _fetchUserInfo(tokens.accessToken);
    final String region = await _fetchRegion(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );

    return RiotSession.fromTokens(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
      entitlementsToken: entitlements,
      puuid: user.puuid,
      gameName: user.gameName,
      tagLine: user.tagLine,
      region: region,
      expiresInSeconds: tokens.expiresIn,
    );
  }

  Future<String> _fetchEntitlementsToken(String accessToken) async {
    final Dio dio = DioFactory.createAuthClient();
    final Response<dynamic> response = await dio.post<dynamic>(
      RiotConstants.entitlementsUrl,
      data: const <String, dynamic>{},
      options: Options(headers: _bearer(accessToken)),
    );
    final String? token =
        _asMap(response.data)['entitlements_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException('Riot did not return an entitlements token.');
    }
    return token;
  }

  Future<_UserInfo> _fetchUserInfo(String accessToken) async {
    final Dio dio = DioFactory.createAuthClient();
    final Response<dynamic> response = await dio.post<dynamic>(
      RiotConstants.userInfoUrl,
      data: const <String, dynamic>{},
      options: Options(headers: _bearer(accessToken)),
    );

    final Map<String, dynamic> body = _asMap(response.data);
    final String? puuid = body['sub'] as String?;
    if (puuid == null || puuid.isEmpty) {
      throw const ApiException('Riot did not return an account id.');
    }
    final Map<String, dynamic> account = _asMap(body['acct']);
    return _UserInfo(
      puuid: puuid,
      gameName: account['game_name'] as String? ?? 'Unknown',
      tagLine: account['tag_line'] as String? ?? '',
    );
  }

  /// Resolves the player's live affinity via Riot's PAS service.
  ///
  /// Falls back to `na` rather than failing the whole sign-in — a wrong shard
  /// produces a clear error on the first storefront call, which is far easier
  /// to act on than a blank login screen.
  Future<String> _fetchRegion({
    required String accessToken,
    required String idToken,
  }) async {
    try {
      final Dio dio = DioFactory.createAuthClient();
      final Response<dynamic> response = await dio.put<dynamic>(
        RiotConstants.geoUrl,
        data: <String, dynamic>{'id_token': idToken},
        options: Options(
          headers: _bearer(accessToken),
          responseType: ResponseType.plain,
        ),
      );
      final String pasToken = '${response.data}'.trim();
      return Jwt.liveAffinity(pasToken) ?? 'na';
    } on Object catch (e) {
      Log.e('Auth', 'Region lookup failed, defaulting to na', e);
      return 'na';
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, String> _bearer(String accessToken) => <String, String>{
    'Authorization': 'Bearer $accessToken',
  };

  /// Pulls the tokens out of `https://playvalorant.com/opt_in#access_token=...`.
  static _TokenPair _parseRedirect(String redirectUri) {
    final String fragment = Uri.parse(redirectUri).fragment;
    if (fragment.isEmpty) {
      throw const ParseException('Riot returned a redirect without tokens.');
    }

    final Map<String, String> params = Uri.splitQueryString(fragment);
    final String? accessToken = params['access_token'];
    if (accessToken == null || accessToken.isEmpty) {
      throw ParseException(
        'Riot returned an error instead of tokens: '
        '${params['error'] ?? 'unknown'}',
      );
    }

    return _TokenPair(
      accessToken: accessToken,
      idToken: params['id_token'] ?? '',
      expiresIn: int.tryParse(params['expires_in'] ?? '') ?? 3600,
    );
  }

  static String? _ssidFromSetCookie(Headers headers) {
    for (final String raw in headers.map['set-cookie'] ?? const <String>[]) {
      final String head = raw.split(';').first.trim();
      final int eq = head.indexOf('=');
      if (eq <= 0) continue;
      if (head.substring(0, eq) == RiotConstants.sessionCookieName) {
        final String value = head.substring(eq + 1);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};

  /// Scheme + host only — safe to log, unlike a URL carrying a token.
  static String _origin(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri == null ? '<unparseable>' : '${uri.scheme}://${uri.host}${uri.path}';
  }
}

class _TokenPair {
  const _TokenPair({
    required this.accessToken,
    required this.idToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String idToken;
  final int expiresIn;
}

class _UserInfo {
  const _UserInfo({
    required this.puuid,
    required this.gameName,
    required this.tagLine,
  });

  final String puuid;
  final String gameName;
  final String tagLine;
}
