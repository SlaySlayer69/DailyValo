import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/riot_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_factory.dart';
import '../../../../core/storage/secure_token_store.dart';
import '../../../../core/utils/jwt.dart';
import '../../../../core/utils/logger.dart';
import '../models/auth_result.dart';
import '../models/riot_session.dart';

/// Riot Sign On + Entitlements, end to end.
///
/// The flow, for anyone reading this later:
///
/// ```
///  POST /api/v1/authorization        -> sets the `asid` cookie, opens a flow
///  PUT  /api/v1/authorization        -> username + password
///        |- type: response           -> tokens in the redirect fragment
///        |- type: multifactor        -> needs a 2FA code, PUT again with it
///        `- type: auth + error       -> bad credentials
///  POST /api/token/v1  (entitlements)-> X-Riot-Entitlements-JWT
///  POST /userinfo                    -> puuid + Riot ID
///  PUT  /pas/v1/product/valorant     -> PAS token, carries the live affinity
/// ```
///
/// Re-authentication later skips all of that: the `ssid` cookie handed out with
/// `remember: true` is replayed against `GET /authorize`, which 303s straight
/// back with a fresh token pair. That is why the password never needs storing.
class RiotAuthApi {
  RiotAuthApi({required SecureTokenStore secureStore})
    : _secureStore = secureStore;

  final SecureTokenStore _secureStore;

  /// Kept alive between [login] and [submitMultifactorCode]: the 2FA `PUT` has
  /// to land on the same RSO flow, which is identified purely by the cookie.
  Dio? _pendingLoginClient;
  CookieJar? _pendingLoginJar;

  // ---------------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------------

  /// Starts a password sign-in.
  ///
  /// [password] is used for exactly one request and is never persisted, logged
  /// or copied anywhere else.
  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final CookieJar jar = CookieJar();
    final Dio dio = DioFactory.createAuthClient(cookieJar: jar);
    _pendingLoginJar = jar;
    _pendingLoginClient = dio;

    // 1. Open an authorization flow. The response body is uninteresting; what
    //    matters is the cookie the server sets.
    await dio.post<dynamic>(
      RiotConstants.authorizationUrl,
      data: <String, dynamic>{
        'client_id': RiotConstants.clientId,
        'nonce': RiotConstants.nonce,
        'redirect_uri': RiotConstants.redirectUri,
        'response_type': RiotConstants.responseType,
        'scope': RiotConstants.scope,
      },
    );

    // 2. Submit credentials into that flow.
    final Response<dynamic> response = await dio.put<dynamic>(
      RiotConstants.authorizationUrl,
      data: <String, dynamic>{
        'type': 'auth',
        'username': username,
        'password': password,
        'remember': true,
        'language': 'en_US',
      },
    );

    return _interpretAuthResponse(response, jar);
  }

  /// Completes a sign-in that Riot interrupted with a 2FA challenge.
  Future<AuthResult> submitMultifactorCode(String code) async {
    final Dio? dio = _pendingLoginClient;
    final CookieJar? jar = _pendingLoginJar;
    if (dio == null || jar == null) {
      return const AuthFailure(
        'That sign-in attempt expired. Please start again.',
        code: 'no_pending_flow',
      );
    }

    final Response<dynamic> response = await dio.put<dynamic>(
      RiotConstants.authorizationUrl,
      data: <String, dynamic>{
        'type': 'multifactor',
        'code': code.trim(),
        'rememberDevice': true,
      },
    );

    return _interpretAuthResponse(response, jar);
  }

  /// Drops any half-finished sign-in (user backed out of the 2FA prompt).
  void abandonPendingLogin() {
    _pendingLoginClient?.close(force: true);
    _pendingLoginClient = null;
    _pendingLoginJar = null;
  }

  Future<AuthResult> _interpretAuthResponse(
    Response<dynamic> response,
    CookieJar jar,
  ) async {
    final Map<String, dynamic> body = _asMap(response.data);
    final String type = body['type'] as String? ?? '';

    switch (type) {
      case 'response':
        final String? uri =
            (_asMap(_asMap(body['response'])['parameters'])['uri'])
                as String?;
        if (uri == null) {
          throw const ParseException(
            'Riot accepted the sign-in but returned no tokens.',
          );
        }
        final _TokenPair tokens = _parseRedirect(uri);
        await _persistSessionCookie(jar);
        final RiotSession session = await _buildSession(tokens);
        abandonPendingLogin();
        return AuthSuccess(session);

      case 'multifactor':
        final Map<String, dynamic> mfa = _asMap(body['multifactor']);
        return AuthMultifactorRequired(
          email: mfa['email'] as String? ?? 'your registered address',
          codeLength: (mfa['multiFactorCodeLength'] as num?)?.toInt() ?? 6,
          method: mfa['method'] as String? ?? 'email',
        );

      case 'auth':
      default:
        final String? error = body['error'] as String?;
        abandonPendingLogin();
        return AuthFailure(_messageForAuthError(error), code: error);
    }
  }

  static String _messageForAuthError(String? code) => switch (code) {
    'auth_failure' => 'Incorrect username or password.',
    'invalid_session_id' => 'That sign-in attempt expired. Please try again.',
    'rate_limited' => 'Too many attempts. Wait a few minutes and try again.',
    'multifactor_attempt_failed' => 'That code is not right. Check and retry.',
    null => 'Sign-in failed. Please try again.',
    _ => 'Sign-in failed ($code).',
  };

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

  Future<void> _persistSessionCookie(CookieJar jar) async {
    final List<Cookie> cookies = await jar.loadForRequest(
      Uri.parse(RiotConstants.authBase),
    );
    for (final Cookie cookie in cookies) {
      if (cookie.name == RiotConstants.sessionCookieName &&
          cookie.value.isNotEmpty) {
        await _secureStore.writeSessionCookie(cookie.value);
        return;
      }
    }
    Log.d('Auth', 'No ssid cookie in the jar — refresh will need a re-login');
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
