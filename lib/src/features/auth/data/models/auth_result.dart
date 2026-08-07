import 'riot_session.dart';

/// Outcome of a sign-in attempt.
///
/// RSO's `PUT /api/v1/authorization` has three meaningful shapes and modelling
/// them as a sealed type means the controller has to handle all of them.
sealed class AuthResult {
  const AuthResult();
}

/// Tokens issued — the user is in.
class AuthSuccess extends AuthResult {
  const AuthSuccess(this.session);

  final RiotSession session;
}

/// Riot wants a 2FA code before it will issue tokens. The auth cookie jar must
/// be kept alive until the code is submitted.
class AuthMultifactorRequired extends AuthResult {
  const AuthMultifactorRequired({
    required this.email,
    required this.codeLength,
    this.method = 'email',
  });

  /// Obfuscated destination, e.g. `k****@g****.com`.
  final String email;
  final int codeLength;
  final String method;
}

/// Wrong credentials, rate limit, or a rejected 2FA code.
class AuthFailure extends AuthResult {
  const AuthFailure(this.message, {this.code});

  final String message;

  /// Raw error code from RSO (`auth_failure`, `rate_limited`, ...).
  final String? code;
}
