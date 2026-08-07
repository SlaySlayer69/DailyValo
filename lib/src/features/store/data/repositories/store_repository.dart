import '../../../../core/constants/storage_keys.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/riot_session_manager.dart';
import '../../../../core/storage/local_store.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/data/models/riot_session.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/repositories/content_repository.dart';
import '../../../wishlist/data/repositories/wishlist_repository.dart';
import '../datasources/demo_store_source.dart';
import '../datasources/riot_store_api.dart';
import '../models/shop.dart';
import '../models/storefront_snapshot.dart';

/// Assembles the shop the UI renders.
///
/// Responsibilities, in order:
///
/// 1. get a raw [StorefrontSnapshot] — from Riot, from the demo generator, or
///    from cache;
/// 2. join it against the content catalogue and the local wishlist/collection;
/// 3. persist the snapshot so the background worker has a "last seen" baseline
///    and a cold start has something to show immediately.
class StoreRepository {
  StoreRepository({
    required RiotStoreApi api,
    required ContentRepository content,
    required WishlistRepository wishlist,
    required RiotSessionManager sessions,
    required LocalStore store,
    DemoStoreSource demo = const DemoStoreSource(),
  }) : _api = api,
       _content = content,
       _wishlist = wishlist,
       _sessions = sessions,
       _store = store,
       _demo = demo;

  final RiotStoreApi _api;
  final ContentRepository _content;
  final WishlistRepository _wishlist;
  final RiotSessionManager _sessions;
  final LocalStore _store;
  final DemoStoreSource _demo;

  bool get isDemoMode => _store.setting<bool>(SettingKeys.demoMode, false);

  /// Loads the current shop.
  ///
  /// Uses the cached snapshot when it has not expired, because the storefront
  /// is genuinely immutable between resets — re-fetching it on every tab switch
  /// would be pure waste and gets the device rate limited.
  Future<Shop> getShop({bool forceRefresh = false}) async {
    final ContentCatalog catalog = await _content.getCatalog();

    StorefrontSnapshot? snapshot;
    if (!forceRefresh) {
      final StorefrontSnapshot? cached = _readCachedSnapshot();
      if (cached != null && !cached.isExpired) snapshot = cached;
    }

    snapshot ??= await _fetchSnapshot();
    await _store.writeCached(CacheKeys.lastShopSnapshot, snapshot.toJson());

    return Shop.resolve(
      snapshot: snapshot,
      catalog: catalog,
      ownedSkinUuids: readCachedOwnedSkins(),
      wishlistedSkinUuids: _wishlist.skinUuids,
    );
  }

  Future<StorefrontSnapshot> _fetchSnapshot() async {
    if (isDemoMode) {
      return _demo.buildStorefront(await _content.getCatalog());
    }
    final RiotSession session = _requireSession();
    return _api.fetchStorefront(shard: session.shard, puuid: session.puuid);
  }

  /// The most recent snapshot on disk, regardless of freshness. Used by the
  /// offline path and by the background worker's change detection.
  StorefrontSnapshot? _readCachedSnapshot() {
    final Map<String, dynamic>? json = _store.readCachedMap(
      CacheKeys.lastShopSnapshot,
    );
    if (json == null) return null;
    try {
      return StorefrontSnapshot.fromJson(json);
    } on Object catch (e) {
      Log.e('Store', 'Cached snapshot unreadable; ignoring', e);
      return null;
    }
  }

  StorefrontSnapshot? get cachedSnapshot => _readCachedSnapshot();

  // ---------------------------------------------------------------------------
  // Collection
  // ---------------------------------------------------------------------------

  /// Refreshes the player's owned skins and caches them.
  Future<Set<String>> refreshOwnedSkins() async {
    final Set<String> owned;
    if (isDemoMode) {
      owned = _demo.buildOwnedSkinLevels(await _content.getCatalog());
    } else {
      final RiotSession session = _requireSession();
      owned = await _api.fetchOwnedSkinLevels(
        shard: session.shard,
        puuid: session.puuid,
      );
    }
    await _store.writeCached(CacheKeys.ownedSkinLevels, owned.toList());
    return owned;
  }

  /// Cached owned-skin level UUIDs. Empty when nothing has synced yet.
  Set<String> readCachedOwnedSkins() {
    final List<dynamic>? raw = _store.readCachedList(
      CacheKeys.ownedSkinLevels,
    );
    if (raw == null) return <String>{};
    return raw.whereType<String>().toSet();
  }

  RiotSession _requireSession() {
    final RiotSession? session = _sessions.session;
    if (session == null) throw const NotAuthenticatedException();
    return session;
  }
}
