import 'dart:convert';

import 'package:dio/dio.dart';

/// Decodes JSON bodies that Dio handed back as a raw [String].
///
/// Dio only parses a response when its `content-type` says JSON. Riot is not
/// consistent about that header across Player Data endpoints: the wallet,
/// storefront and entitlements routes announce `application/json` and decode
/// normally, while the MMR routes do not — they return the same JSON with a
/// content type Dio does not recognise.
///
/// The failure that caused was entirely silent. Every map lookup against a
/// String yields nothing, so a 19 KB MMR record read as "no rank" and the app
/// confidently displayed *Unranked* for a ranked player. Nothing threw and no
/// status code was wrong.
///
/// Normalising here rather than at each call site means the next endpoint Riot
/// adds with a sloppy content type simply works.
class JsonResponseInterceptor extends Interceptor {
  const JsonResponseInterceptor();

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final Object? data = response.data;
    if (data is String && data.isNotEmpty) {
      final String trimmed = data.trimLeft();
      // Only touch things that actually look like JSON. Some endpoints return
      // a bare token as text — the PAS/geo response is a raw JWT — and those
      // must survive untouched.
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          response.data = jsonDecode(data);
        } on FormatException {
          // Leave the original string in place; the caller can still inspect
          // it, and pretending we parsed it would be worse.
        }
      }
    }
    handler.next(response);
  }
}
