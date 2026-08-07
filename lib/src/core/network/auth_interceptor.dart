import 'package:dio/dio.dart';

import '../../features/auth/data/models/riot_session.dart';
import '../constants/riot_constants.dart';
import '../errors/app_exception.dart';
import '../utils/logger.dart';
import 'client_version.dart';
import 'riot_session_manager.dart';

/// Attaches Riot's four required headers to every PD request and transparently
/// recovers from an expired access token.
///
/// PD answers `400`/`401` (it is inconsistent) when the bearer token has
/// lapsed. On the first such failure we refresh once and replay the request;
/// a second failure is surfaced to the caller so we can never loop.
class RiotAuthInterceptor extends Interceptor {
  RiotAuthInterceptor({
    required RiotSessionManager sessionManager,
    required ClientVersionHolder clientVersion,
    required Dio retryClient,
  }) : _sessions = sessionManager,
       _clientVersion = clientVersion,
       _retryClient = retryClient;

  static const String _retriedFlag = 'dv.retried';

  final RiotSessionManager _sessions;
  final ClientVersionHolder _clientVersion;

  /// Used to replay the failed request. Must be a Dio instance *without* this
  /// interceptor, otherwise a replay could recurse.
  final Dio _retryClient;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final RiotSession session = await _sessions.requireValidSession();
      _applyHeaders(options, session);
      handler.next(options);
    } on AppException catch (e) {
      handler.reject(
        DioException(requestOptions: options, error: e, type: DioExceptionType.cancel),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int? status = err.response?.statusCode;
    final bool looksExpired = status == 401 || status == 400;
    final bool alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    if (!looksExpired || alreadyRetried) {
      handler.next(err);
      return;
    }

    Log.d('Auth', 'PD returned $status — refreshing tokens and replaying');
    try {
      final RiotSession session = await _sessions.refresh();
      final RequestOptions retryOptions = err.requestOptions
        ..extra[_retriedFlag] = true;
      _applyHeaders(retryOptions, session);

      final Response<dynamic> response = await _retryClient.fetch<dynamic>(
        retryOptions,
      );
      handler.resolve(response);
    } on Object catch (e) {
      // Refresh failed: hand the *original* error back, it is more informative.
      Log.e('Auth', 'Token refresh during retry failed', e);
      handler.next(err);
    }
  }

  void _applyHeaders(RequestOptions options, RiotSession session) {
    options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    options.headers['X-Riot-Entitlements-JWT'] = session.entitlementsToken;
    options.headers['X-Riot-ClientPlatform'] = RiotConstants.clientPlatform;
    options.headers['X-Riot-ClientVersion'] = _clientVersion.value;
  }
}
