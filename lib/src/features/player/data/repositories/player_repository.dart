import '../../../../core/constants/storage_keys.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/riot_session_manager.dart';
import '../../../../core/storage/local_store.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/data/models/riot_session.dart';
import '../../../content/data/repositories/content_repository.dart';
import '../../../store/data/datasources/demo_store_source.dart';
import '../../../store/data/datasources/riot_store_api.dart';
import '../../../store/data/models/competitive_standing.dart';
import '../models/player_profile.dart';

/// Builds the profile shown in the app header: Riot ID, rank, VP and RP.
class PlayerRepository {
  PlayerRepository({
    required RiotStoreApi api,
    required RiotSessionManager sessions,
    required LocalStore store,
    required ContentRepository content,
    DemoStoreSource demo = const DemoStoreSource(),
  }) : _api = api,
       _sessions = sessions,
       _store = store,
       _content = content,
       _demo = demo;

  final RiotStoreApi _api;
  final RiotSessionManager _sessions;
  final LocalStore _store;
  final ContentRepository _content;
  final DemoStoreSource _demo;

  bool get _isDemoMode => _store.setting<bool>(SettingKeys.demoMode, false);

  /// Last known profile, available synchronously so the header never flashes
  /// empty while the network call is in flight.
  PlayerProfile? get cached {
    final Map<String, dynamic>? json = _store.readCachedMap(
      CacheKeys.playerProfile,
    );
    if (json == null) return null;
    try {
      return PlayerProfile.fromJson(json);
    } on Object catch (e) {
      Log.e('Player', 'Cached profile unreadable', e);
      return null;
    }
  }

  Future<PlayerProfile> refresh() async {
    final PlayerProfile profile = _isDemoMode
        ? _buildDemoProfile()
        : await _fetchLiveProfile();

    await _store.writeCached(CacheKeys.playerProfile, profile.toJson());
    return profile;
  }

  /// Builds the live profile.
  ///
  /// Every part is fetched independently and every failure is contained. The
  /// header must never go blank: the Riot ID comes from the session and needs
  /// no network at all, so there is no failure mode in which we know nothing
  /// about the player. An earlier version gathered wallet and rank with
  /// `(a, b).wait`, which throws if *either* side fails — one unavailable
  /// endpoint took out the entire header, Riot ID included.
  Future<PlayerProfile> _fetchLiveProfile() async {
    final RiotSession? session = _sessions.session;
    if (session == null) throw const NotAuthenticatedException();

    final Wallet? wallet = await _tryWallet(session);
    final CompetitiveStanding? standing = await _tryStanding(session);

    return PlayerProfile(
      puuid: session.puuid,
      gameName: session.gameName,
      tagLine: session.tagLine,
      wallet: wallet ?? Wallet.empty,
      walletKnown: wallet != null,
      competitiveTier: standing?.tier ?? 0,
      rankedRating: standing?.rankedRating ?? 0,
      rankKnown: standing != null,
      updatedAt: DateTime.now(),
    );
  }

  Future<Wallet?> _tryWallet(RiotSession session) async {
    try {
      return await _api.fetchWallet(
        shard: session.shard,
        puuid: session.puuid,
      );
    } on Object catch (e) {
      Log.e('Player', 'Wallet unavailable', e);
      return null;
    }
  }

  Future<CompetitiveStanding?> _tryStanding(RiotSession session) async {
    try {
      // The act uuid keys the MMR record. Cached, so usually free — and its
      // own failure must not cost us the rank, let alone the whole header.
      final List<String> actUuids = await _content.actUuidsNewestFirst();
      return await _api.fetchCompetitiveStanding(
        shard: session.shard,
        puuid: session.puuid,
        actUuids: actUuids,
      );
    } on Object catch (e) {
      Log.e('Player', 'Competitive standing unavailable', e);
      return null;
    }
  }

  PlayerProfile _buildDemoProfile() {
    final CompetitiveStanding standing = _demo.buildCompetitiveStanding();
    return PlayerProfile(
      puuid: 'demo-puuid',
      gameName: 'SlaySlayer',
      tagLine: '161',
      wallet: _demo.buildWallet(),
      competitiveTier: standing.tier,
      rankedRating: standing.rankedRating,
      updatedAt: DateTime.now(),
    );
  }
}
