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
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> readSession() => _guard(
    () => _storage.read(key: SecureKeys.session),
    'read session',
  );

  Future<void> writeSession(String json) => _guard(
    () => _storage.write(key: SecureKeys.session, value: json),
    'write session',
  );

  Future<String?> readSessionCookie() => _guard(
    () => _storage.read(key: SecureKeys.sessionCookie),
    'read session cookie',
  );

  Future<void> writeSessionCookie(String value) => _guard(
    () => _storage.write(key: SecureKeys.sessionCookie, value: value),
    'write session cookie',
  );

  /// Wipes every credential. Called on sign-out and whenever a refresh fails
  /// in a way that means the session is gone for good.
  Future<void> clear() => _guard(() async {
    await _storage.delete(key: SecureKeys.session);
    await _storage.delete(key: SecureKeys.sessionCookie);
  }, 'clear credentials');

  Future<T> _guard<T>(Future<T> Function() action, String what) async {
    try {
      return await action();
    } on Object catch (e) {
      throw StorageException('Secure storage failed to $what.', cause: e);
    }
  }
}
