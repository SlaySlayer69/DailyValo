import 'package:dio/dio.dart';

import '../utils/logger.dart';

/// Records every request the app makes, while file logging is on.
///
/// The failures this app has actually had were all of the shape "one endpoint
/// behaved differently than assumed" — a missing JSON content type, a 403 on a
/// refresh, a storefront that answered but with nothing in it. None of them are
/// visible from the UI, because the repositories absorb failures on purpose so
/// one dead endpoint cannot blank the screen. This is where that information
/// goes instead.
///
/// Bodies are logged truncated, and everything passes through the redaction in
/// the log sink before it reaches the file. The truncation is not about
/// secrets — it is that the skin catalogue is megabytes and would bury the four
/// lines anybody is looking for.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this.label);

  /// Which client this is — `auth`, `game`, `content`. Three Dio instances talk
  /// to three different hosts with different rules, and a log that did not say
  /// which was which would be much harder to read.
  final String label;

  static const int _maxBody = 600;
  static const String _startedAt = 'dv.startedAt';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.extra[_startedAt] = DateTime.now();
    Log.t(
      'Net/$label',
      '→ ${options.method} ${options.uri}'
      '${_body('body', options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    Log.t(
      'Net/$label',
      '← ${response.statusCode} ${response.requestOptions.uri}'
      ' ${_elapsed(response.requestOptions)}'
      '${_body('body', response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Log.w(
      'Net/$label',
      '✗ ${err.type.name} ${err.requestOptions.uri}'
      ' ${_elapsed(err.requestOptions)}'
      '${err.response == null ? '' : ' status ${err.response?.statusCode}'}'
      '${_body('body', err.response?.data)}',
    );
    handler.next(err);
  }

  static String _elapsed(RequestOptions options) {
    final Object? started = options.extra[_startedAt];
    if (started is! DateTime) return '';
    return '(${DateTime.now().difference(started).inMilliseconds}ms)';
  }

  static String _body(String name, Object? data) {
    if (data == null) return '';
    final String text = data.toString();
    if (text.isEmpty) return '';
    final String clipped = text.length <= _maxBody
        ? text
        : '${text.substring(0, _maxBody)}… (${text.length} chars)';
    return '\n    $name: $clipped';
  }
}
