/// Every failure the app surfaces to the UI is one of these, so widgets never
/// have to reason about `DioException`, `FormatException`, platform errors, ...
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connectivity, DNS failure, timeout.
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'Could not reach the server. Check your connection.',
  ]);
}

/// Riot rejected the credentials, or the stored session can no longer be
/// refreshed and the user has to sign in again.
class AuthException extends AppException {
  const AuthException(super.message, {super.cause, this.requiresReLogin = false});

  final bool requiresReLogin;
}

/// The API answered, but not with something we can use.
class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode, super.cause});

  final int? statusCode;
}

/// Response body did not match the shape we expect.
class ParseException extends AppException {
  const ParseException(super.message, {super.cause});
}

/// Reading or writing local storage failed.
class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// The action needs a signed-in account and there isn't one.
class NotAuthenticatedException extends AppException {
  const NotAuthenticatedException([
    super.message = 'Sign in with your Riot account to see your shop.',
  ]);
}
