import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../constants/storage_keys.dart';
import '../utils/logger.dart';

/// Thin, typed façade over the app's Hive boxes.
///
/// Values are stored as JSON strings rather than through generated
/// `TypeAdapter`s. That is a deliberate trade: it costs a little CPU on read,
/// and in exchange there is no `build_runner` step, no adapter-registry drift
/// between the UI isolate and the background isolate, and a schema change is
/// just a `fromJson` that tolerates a missing field.
class LocalStore {
  LocalStore._(this._wishlist, this._cache, this._settings);

  final Box<String> _wishlist;
  final Box<String> _cache;
  final Box<dynamic> _settings;

  static LocalStore? _instance;

  /// Whether [init] has already run in this isolate.
  static bool get isReady => _instance != null;

  static LocalStore get instance {
    final LocalStore? i = _instance;
    if (i == null) {
      throw StateError('LocalStore.init() must be awaited before use.');
    }
    return i;
  }

  /// Opens the boxes. Safe to call from the background isolate too — Hive is
  /// per-isolate, so the worker calls this exactly like `main()` does.
  static Future<LocalStore> init() async {
    final LocalStore? existing = _instance;
    if (existing != null) return existing;

    await Hive.initFlutter('dailyvalo');
    final Box<String> wishlist = await Hive.openBox<String>(HiveBoxes.wishlist);
    final Box<String> cache = await Hive.openBox<String>(HiveBoxes.cache);
    final Box<dynamic> settings = await Hive.openBox<dynamic>(
      HiveBoxes.settings,
    );

    return _instance = LocalStore._(wishlist, cache, settings);
  }

  /// Opens the boxes against an explicit directory.
  ///
  /// Test-only: [init] goes through `Hive.initFlutter`, which needs the
  /// `path_provider` plugin — unavailable in a plain `flutter test` run.
  @visibleForTesting
  static Future<LocalStore> initAt(String path) async {
    await reset();
    Hive.init(path);
    return _instance = LocalStore._(
      await Hive.openBox<String>(HiveBoxes.wishlist),
      await Hive.openBox<String>(HiveBoxes.cache),
      await Hive.openBox<dynamic>(HiveBoxes.settings),
    );
  }

  /// Closes every box and forgets the singleton. Test-only.
  @visibleForTesting
  static Future<void> reset() async {
    _instance = null;
    await Hive.close();
  }

  // ---------------------------------------------------------------------------
  // Wishlist — one entry per skin UUID.
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> readWishlist() {
    return _wishlist.values
        .map(_decodeMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> putWishlistEntry(String skinUuid, Map<String, dynamic> json) =>
      _wishlist.put(skinUuid, jsonEncode(json));

  Future<void> deleteWishlistEntry(String skinUuid) =>
      _wishlist.delete(skinUuid);

  bool isWishlisted(String skinUuid) => _wishlist.containsKey(skinUuid);

  Set<String> wishlistedSkinUuids() => _wishlist.keys.cast<String>().toSet();

  // ---------------------------------------------------------------------------
  // Cache — API payloads that survive restarts.
  // ---------------------------------------------------------------------------
  Map<String, dynamic>? readCachedMap(String key) {
    final String? raw = _cache.get(key);
    return raw == null ? null : _decodeMap(raw);
  }

  List<dynamic>? readCachedList(String key) {
    final String? raw = _cache.get(key);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } on FormatException catch (e) {
      Log.e('LocalStore', 'Corrupt cache list at $key', e);
      return null;
    }
  }

  Future<void> writeCached(String key, Object value) =>
      _cache.put(key, jsonEncode(value));

  String? readCachedString(String key) => _cache.get(key);

  Future<void> writeCachedString(String key, String value) =>
      _cache.put(key, value);

  Future<void> deleteCached(String key) => _cache.delete(key);

  Future<void> clearCache() => _cache.clear();

  // ---------------------------------------------------------------------------
  // Settings — scalars only.
  // ---------------------------------------------------------------------------
  T setting<T>(String key, T fallback) {
    final Object? value = _settings.get(key);
    return value is T ? value : fallback;
  }

  Future<void> putSetting(String key, Object? value) =>
      _settings.put(key, value);

  /// Drops user-scoped data on sign-out. The content catalogue is intentionally
  /// kept — it is public, expensive to fetch, and identical for every account.
  Future<void> clearUserData() async {
    await _cache.delete(CacheKeys.lastShopSnapshot);
    await _cache.delete(CacheKeys.ownedSkinLevels);
    await _cache.delete(CacheKeys.playerProfile);
  }

  static Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException catch (e) {
      Log.e('LocalStore', 'Corrupt JSON in box', e);
      return null;
    }
  }
}
