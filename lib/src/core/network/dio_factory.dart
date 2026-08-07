import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../constants/riot_constants.dart';
import 'auth_interceptor.dart';
import 'client_version.dart';
import 'error_interceptor.dart';
import 'riot_session_manager.dart';

/// Builds the three HTTP clients the app needs. They are deliberately separate:
/// the auth flow needs cookies and must *not* carry bearer tokens, the game API
/// needs bearer tokens and must not carry cookies, and the content CDN needs
/// neither.
abstract final class DioFactory {
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 20);

  /// Client for `auth.riotgames.com` and friends.
  ///
  /// RSO's login is cookie-driven: `POST /api/v1/authorization` sets an `asid`
  /// cookie that the subsequent `PUT` must echo back, so a cookie jar is not
  /// optional here. The jar is in-memory on purpose — see [SecureTokenStore]
  /// for why the durable half of that state lives in the keystore instead.
  static Dio createAuthClient({CookieJar? cookieJar}) {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        headers: <String, String>{
          'User-Agent': RiotConstants.userAgent,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        // The auth flow reads 3xx/4xx bodies itself, so don't throw on them.
        validateStatus: (int? status) => status != null && status < 500,
      ),
    );
    dio.interceptors.add(CookieManager(cookieJar ?? CookieJar()));
    dio.interceptors.add(const ErrorMappingInterceptor());
    return dio;
  }

  /// Client for the Player Data endpoints (`pd.{shard}.a.pvp.net`).
  static Dio createGameClient({
    required RiotSessionManager sessionManager,
    required ClientVersionHolder clientVersion,
  }) {
    final BaseOptions options = BaseOptions(
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: <String, String>{
        'User-Agent': RiotConstants.userAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

    // A twin without the auth interceptor, used to replay refreshed requests.
    final Dio replayClient = Dio(options);

    final Dio dio = Dio(options);
    dio.interceptors.add(
      RiotAuthInterceptor(
        sessionManager: sessionManager,
        clientVersion: clientVersion,
        retryClient: replayClient,
      ),
    );
    dio.interceptors.add(const ErrorMappingInterceptor());
    return dio;
  }

  /// Client for `valorant-api.com`. Public, unauthenticated, cacheable.
  static Dio createContentClient() {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        // The full weapon catalogue is a few MB of JSON on a cold cache.
        receiveTimeout: const Duration(seconds: 45),
        headers: <String, String>{'Accept': 'application/json'},
      ),
    );
    dio.interceptors.add(const ErrorMappingInterceptor());
    return dio;
  }
}
