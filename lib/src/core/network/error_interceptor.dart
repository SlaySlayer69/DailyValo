import 'dart:io';

import 'package:dio/dio.dart';

import '../errors/app_exception.dart';

/// Converts Dio's failure modes into the app's [AppException] family.
///
/// Runs last in the chain so that by the time an error reaches a repository,
/// `err.error` is always something the UI knows how to render.
class ErrorMappingInterceptor extends Interceptor {
  const ErrorMappingInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Already mapped (e.g. by the auth interceptor) — leave it alone.
    if (err.error is AppException) {
      handler.next(err);
      return;
    }

    final AppException mapped = _map(err);
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: mapped,
        stackTrace: err.stackTrace,
      ),
    );
  }

  AppException _map(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkException('The request timed out. Try again.');
      case DioExceptionType.connectionError:
        return const NetworkException();
      case DioExceptionType.badCertificate:
        return const NetworkException(
          'The connection could not be verified. Are you on a proxy?',
        );
      case DioExceptionType.cancel:
        return const ApiException('Request cancelled.');
      case DioExceptionType.unknown:
        if (err.error is SocketException) return const NetworkException();
        return ApiException(
          'Something went wrong talking to the server.',
          cause: err.error,
        );
      case DioExceptionType.badResponse:
        return _mapStatus(err);
    }
  }

  AppException _mapStatus(DioException err) {
    final int status = err.response?.statusCode ?? 0;
    return switch (status) {
      400 || 401 || 403 => const AuthException(
        'Your Riot session expired. Please sign in again.',
        requiresReLogin: true,
      ),
      404 => const ApiException('Not found.', statusCode: 404),
      429 => const ApiException(
        'Riot is rate limiting this device. Wait a minute and retry.',
        statusCode: 429,
      ),
      >= 500 => ApiException(
        'Riot\'s servers are having a moment. Try again shortly.',
        statusCode: status,
      ),
      _ => ApiException('Unexpected response ($status).', statusCode: status),
    };
  }
}
