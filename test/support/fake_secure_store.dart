import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/errors/app_exception.dart';
import 'package:dailyvalo/src/core/storage/secure_token_store.dart';

/// An in-memory stand-in for the Android Keystore.
///
/// The real store goes through `flutter_secure_storage`, whose platform channel
/// does not exist in a `flutter test` run. Everything the migration does to
/// credentials happens through these methods, so overriding them exercises the
/// real logic against a map.
class FakeSecureStore extends SecureTokenStore {
  FakeSecureStore({String accountId = ''}) : super.unscoped() {
    _accountId = accountId;
  }

  late String _accountId;

  final Map<String, String> values = <String, String>{};

  /// Makes the next write throw, to prove a half-finished migration is retried
  /// rather than marked done.
  bool failOnWrite = false;

  void _guardWrite() {
    if (failOnWrite) {
      throw const StorageException('Secure storage failed to write.');
    }
  }

  @override
  String get accountId => _accountId;

  @override
  Future<String?> readSession() async => values[SecureKeys.session(accountId)];

  @override
  Future<void> writeSession(String json) async {
    _guardWrite();
    values[SecureKeys.session(accountId)] = json;
  }

  @override
  Future<String?> readSessionCookie() async =>
      values[SecureKeys.sessionCookie(accountId)];

  @override
  Future<void> writeSessionCookie(String value) async {
    _guardWrite();
    values[SecureKeys.sessionCookie(accountId)] = value;
  }

  @override
  Future<void> clear() async {
    values.remove(SecureKeys.session(accountId));
    values.remove(SecureKeys.sessionCookie(accountId));
  }

  @override
  Future<String?> readLegacySession() async =>
      values[SecureKeys.legacySession];

  @override
  Future<String?> readLegacySessionCookie() async =>
      values[SecureKeys.legacySessionCookie];

  @override
  Future<void> writeSessionFor(String id, String json) async {
    _guardWrite();
    values[SecureKeys.session(id)] = json;
  }

  @override
  Future<void> writeSessionCookieFor(String id, String value) async {
    _guardWrite();
    values[SecureKeys.sessionCookie(id)] = value;
  }

  @override
  Future<void> clearLegacy() async {
    values.remove(SecureKeys.legacySession);
    values.remove(SecureKeys.legacySessionCookie);
  }
}
