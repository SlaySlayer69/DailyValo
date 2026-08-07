import 'dart:async';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/network/client_version.dart';
import '../../../../core/storage/local_store.dart';
import '../../../../core/utils/logger.dart';
import '../datasources/valorant_api_client.dart';
import '../models/accessory_item.dart';
import '../models/content_catalog.dart';
import '../models/content_tier.dart';
import '../models/weapon_skin.dart';

/// Owns the static content catalogue and its cache policy.
///
/// The catalogue is ~4 MB of JSON and changes only on patch day, so:
///
/// * a cached copy is returned immediately, even when stale;
/// * a stale copy triggers a background refresh that swaps in silently;
/// * a network failure with a cache present is not an error.
///
/// That is what lets the shop tab render instantly on a cold start, and at all
/// on a plane.
class ContentRepository {
  ContentRepository({
    required ValorantApiClient client,
    required LocalStore store,
    required ClientVersionHolder clientVersion,
  }) : _client = client,
       _store = store,
       _clientVersion = clientVersion;

  final ValorantApiClient _client;
  final LocalStore _store;
  final ClientVersionHolder _clientVersion;

  ContentCatalog? _memory;

  /// Returns the catalogue, fetching only when there is nothing usable cached.
  ///
  /// Set [forceRefresh] for pull-to-refresh.
  Future<ContentCatalog> getCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final ContentCatalog? cached = _memory ?? _readCache();
      if (cached != null && cached.language == _client.language) {
        _memory = cached;
        if (cached.isStale) {
          // Fire-and-forget: the user gets the cached copy now, and the next
          // read gets the fresh one.
          _fireAndForget(_refresh(), 'stale catalogue refresh');
        }
        return cached;
      }
    }
    return _refresh();
  }

  /// The synchronously available catalogue, if one has already been loaded.
  /// Used by widgets that must not suspend (e.g. the notification builder).
  ContentCatalog? get cached => _memory ?? _readCache();

  Future<ContentCatalog> _refresh() async {
    Log.d('Content', 'Fetching catalogue (${_client.language})');

    // Independent requests — no reason to serialise them.
    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      _client.fetchSkins(),
      _client.fetchContentTiers(),
      _client.fetchCompetitiveTiers(),
      _client.fetchAccessories(),
      _client.fetchBundles(),
    ]);

    final ContentCatalog catalog = ContentCatalog(
      skins: results[0] as List<WeaponSkin>,
      tiers: results[1] as Map<String, ContentTier>,
      competitiveTiers: results[2] as Map<int, CompetitiveTier>,
      accessories: results[3] as Map<String, AccessoryItem>,
      bundles: results[4] as Map<String, BundleInfo>,
      language: _client.language,
      fetchedAt: DateTime.now(),
    );

    _memory = catalog;
    await _store.writeCached(CacheKeys.contentCatalog, catalog.toJson());
    Log.d(
      'Content',
      'Catalogue ready: ${catalog.skins.length} skins, '
          '${catalog.accessories.length} accessory ids, '
          '${catalog.bundles.length} bundles',
    );
    return catalog;
  }

  /// UUID of the current act, cached for a day.
  ///
  /// Kept out of the catalogue blob deliberately: acts roll over on their own
  /// schedule, and a user sitting on a fresh 24-hour catalogue cache should
  /// still get a correct rank the day an act flips.
  Future<String?> currentActUuid() async {
    final String? cached = _store.readCachedString(CacheKeys.currentActUuid);
    final DateTime? fetchedAt = DateTime.tryParse(
      _store.readCachedString(CacheKeys.currentActFetchedAt) ?? '',
    );
    final bool fresh =
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(hours: 24);
    if (cached != null && cached.isNotEmpty && fresh) return cached;

    try {
      final String? uuid = await _client.fetchCurrentActUuid();
      if (uuid != null && uuid.isNotEmpty) {
        await _store.writeCachedString(CacheKeys.currentActUuid, uuid);
        await _store.writeCachedString(
          CacheKeys.currentActFetchedAt,
          DateTime.now().toIso8601String(),
        );
        return uuid;
      }
    } on Object catch (e) {
      Log.e('Content', 'Current act lookup failed', e);
    }
    // A stale value still beats none: acts run for weeks.
    return cached;
  }

  List<String>? _actUuids;

  /// Act uuids newest first, so a rank lookup can walk back through acts.
  Future<List<String>> actUuidsNewestFirst() async {
    final List<String>? cached = _actUuids;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      return _actUuids = await _client.fetchActUuidsNewestFirst();
    } on Object catch (e) {
      Log.e('Content', 'Act list lookup failed', e);
      final String? current = await currentActUuid();
      return _actUuids = current == null ? <String>[] : <String>[current];
    }
  }

  Future<void>? _versionSync;

  /// Refreshes the `X-Riot-ClientVersion` used by PD requests.
  ///
  /// Memoised, so callers that need the header to be current can simply await
  /// it without causing a second fetch. Bounded and best-effort: a
  /// stale-but-plausible version still works for most endpoints, and failing
  /// app start over a third-party CDN would be absurd.
  Future<void> syncClientVersion() =>
      _versionSync ??= _doSyncClientVersion();

  Future<void> _doSyncClientVersion() async {
    try {
      final String version = await _client.fetchClientVersion().timeout(
        const Duration(seconds: 8),
      );
      await _clientVersion.update(version);
      Log.d('Content', 'Client version: $version');
    } on Object catch (e) {
      Log.e('Content', 'Client version sync failed; keeping cached value', e);
      // Do not memoise a failure for the life of the process.
      _versionSync = null;
    }
  }

  ContentCatalog? _readCache() {
    final Map<String, dynamic>? json = _store.readCachedMap(
      CacheKeys.contentCatalog,
    );
    if (json == null) return null;
    try {
      return ContentCatalog.fromJson(json);
    } on Object catch (e) {
      Log.e('Content', 'Cached catalogue was unreadable; dropping it', e);
      _fireAndForget(
        _store.deleteCached(CacheKeys.contentCatalog),
        'drop corrupt catalogue',
      );
      return null;
    }
  }

  /// Starts work we deliberately do not wait on, while still logging failures
  /// instead of letting them surface as an unhandled async error.
  static void _fireAndForget(Future<void> future, String what) {
    unawaited(
      future.catchError((Object e, StackTrace st) {
        Log.e('Content', 'Failed to $what', e, st);
      }),
    );
  }
}
