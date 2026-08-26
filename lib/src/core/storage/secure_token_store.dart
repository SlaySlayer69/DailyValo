import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';
import '../errors/app_exception.dart';

/// Everything credential-shaped lives here and nowhere else.
///
/// Backed by the Android Keystore (AES-GCM with an RSA-wrapped key) via
/// `flutter_secure_storage`. Two design rules this class exists to enforce:
///
/// 1. **The password is never written to disk.** It is passed to
///    [RiotAuthApi.login] and discarded. What we persist instead is the RSO
///    `ssid` cookie, which can be revoked server-side by the user and is
///    useless without Riot's own signing key.
/// 2. **Nothing here touches Hive.** Hive boxes are plain files; tokens must
///    not end up in one, including via a debug dump.
class SecureTokenStore {
  SecureTokenStore({required this.accountId, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// For the migration and for device-wide work, which needs the legacy keys
  /// and nothing account-scoped.
  SecureTokenStore.unscoped({FlutterSecureStorage? storage})
    : accountId = '',
      _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Which account's credentials this instance reads and writes.
  ///
  /// Bound at construction rather than passed per call: a store that could be
  /// asked for "the session" without saying whose is exactly how one account's
  /// tokens end up under another's name.
  final String accountId;

  Future<String?> readSession() => _guard(
    () => _storage.read(key: SecureKeys.session(accountId)),
    'read session',
  );

  Future<void> writeSession(String json) => _guard(
    () => _storage.write(key: SecureKeys.session(accountId), value: json),
    'write session',
  );

  Future<String?> readSessionCookie() => _guard(
    () => _storage.read(key: SecureKeys.sessionCookie(accountId)),
    'read session cookie',
  );

  Future<void> writeSessionCookie(String value) => _guard(
    () => _storage.write(key: SecureKeys.sessionCookie(accountId), value: value),
    'write session cookie',
  );

  /// Wipes this account's credentials. Called when it is signed out, and
  /// whenever a refresh fails in a way that means its session is gone for good.
  Future<void> clear() => _guard(() async {
    await _storage.delete(key: SecureKeys.session(accountId));
    await _storage.delete(key: SecureKeys.sessionCookie(accountId));
  }, 'clear credentials');

  // --- Migration ------------------------------------------------------------
  //
  // The single-account keys, reachable regardless of [accountId] because the
  // whole point is to read them before any account is known.

  Future<String?> readLegacySession() => _guard(
    () => _storage.read(key: SecureKeys.legacySession),
    'read the previous session',
  );

  Future<String?> readLegacySessionCookie() => _guard(
    () => _storage.read(key: SecureKeys.legacySessionCookie),
    'read the previous session cookie',
  );

  Future<void> writeSessionFor(String id, String json) => _guard(
    () => _storage.write(key: SecureKeys.session(id), value: json),
    'write session',
  );

  Future<void> writeSessionCookieFor(String id, String value) => _guard(
    () => _storage.write(key: SecureKeys.sessionCookie(id), value: value),
    'write session cookie',
  );

  Future<void> clearLegacy() => _guard(() async {
    await _storage.delete(key: SecureKeys.legacySession);
    await _storage.delete(key: SecureKeys.legacySessionCookie);
  }, 'clear the previous credentials');

  Future<T> _guard<T>(Future<T> Function() action, String what) async {
    try {
      return await action();
    } on Object catch (e) {
      throw StorageException('Secure storage failed to $what.', cause: e);
    }
  }
}
