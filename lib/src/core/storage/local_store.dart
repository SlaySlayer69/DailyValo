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
  // Wishlist — one entry per skin UUID, per account.
  // ---------------------------------------------------------------------------
  //
  // One box with composite keys rather than a box per account: Hive boxes are
  // files that have to be opened before use, and the background worker walks
  // every account in turn. Prefixing is one string concatenation; opening N
  // boxes is N file handles and N failure modes.

  static String _wishlistKey(String accountId, String skinUuid) =>
      '$accountId|$skinUuid';

  List<Map<String, dynamic>> readWishlist(String accountId) {
    final String prefix = '$accountId|';
    return _wishlist.keys
        .cast<String>()
        .where((String k) => k.startsWith(prefix))
        .map((String k) => _wishlist.get(k))
        .whereType<String>()
        .map(_decodeMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> putWishlistEntry(
    String accountId,
    String skinUuid,
    Map<String, dynamic> json,
  ) => _wishlist.put(_wishlistKey(accountId, skinUuid), jsonEncode(json));

  Future<void> deleteWishlistEntry(String accountId, String skinUuid) =>
      _wishlist.delete(_wishlistKey(accountId, skinUuid));

  bool isWishlisted(String accountId, String skinUuid) =>
      _wishlist.containsKey(_wishlistKey(accountId, skinUuid));

  Set<String> wishlistedSkinUuids(String accountId) {
    final String prefix = '$accountId|';
    return _wishlist.keys
        .cast<String>()
        .where((String k) => k.startsWith(prefix))
        .map((String k) => k.substring(prefix.length))
        .toSet();
  }

  /// Gives every unscoped wishlist entry to [accountId].
  ///
  /// The single-account layout keyed entries by skin UUID alone. Left as they
  /// were they would belong to nobody and simply vanish, which is the one
  /// piece of data in this app the user actually curated by hand.
  Future<void> adoptUnscopedWishlist(String accountId) async {
    final List<String> legacy = _wishlist.keys
        .cast<String>()
        .where((String k) => !k.contains('|'))
        .toList(growable: false);

    for (final String key in legacy) {
      final String? value = _wishlist.get(key);
      if (value == null) continue;
      await _wishlist.put(_wishlistKey(accountId, key), value);
      await _wishlist.delete(key);
    }
  }

  /// Writes a wishlist entry the way the single-account layout did: keyed by
  /// skin UUID alone, with no account prefix.
  ///
  /// Test-only, and it exists so the migration can be tested against the shape
  /// it actually has to handle rather than an approximation of it.
  @visibleForTesting
  Future<void> putUnscopedWishlistEntry(
    String skinUuid,
    Map<String, dynamic> json,
  ) => _wishlist.put(skinUuid, jsonEncode(json));

  /// Moves one cached value to a new key, if it is there.
  Future<void> moveCached(String from, String to) async {
    final String? value = _cache.get(from);
    if (value == null) return;
    await _cache.put(to, value);
    await _cache.delete(from);
  }

  /// Drops one account's cached server data.
  ///
  /// The **wishlist is deliberately kept**. It is the only thing in this app
  /// the user assembled by hand, it is worth nothing to anyone else, and
  /// per-account keys mean it can only ever be picked up again by the same
  /// puuid — so signing out and back in restores it instead of starting from
  /// an empty list. Everything else here is a copy of something Riot will hand
  /// back on the next request.
  Future<void> clearAccountCaches(String accountId) async {
    for (final String key in <String>[
      CacheKeys.shopSnapshot(accountId),
      CacheKeys.notifiedOfferIds(accountId),
      CacheKeys.ownedSkinLevels(accountId),
      CacheKeys.playerProfile(accountId),
    ]) {
      await _cache.delete(key);
    }
  }

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
  Future<void> clearUserData(String accountId) => clearAccountCaches(accountId);

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
