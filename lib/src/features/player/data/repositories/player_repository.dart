import '../../../../core/constants/storage_keys.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/riot_session_manager.dart';
import '../../../../core/storage/local_store.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/data/models/riot_session.dart';
import '../../../store/data/datasources/demo_store_source.dart';
import '../../../store/data/datasources/riot_store_api.dart';
import '../models/player_profile.dart';

/// Builds the profile shown in the app header: Riot ID, rank, VP and RP.
class PlayerRepository {
  PlayerRepository({
    required RiotStoreApi api,
    required RiotSessionManager sessions,
    required LocalStore store,
    DemoStoreSource demo = const DemoStoreSource(),
  }) : _api = api,
       _sessions = sessions,
       _store = store,
       _demo = demo;

  final RiotStoreApi _api;
  final RiotSessionManager _sessions;
  final LocalStore _store;
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

  Future<PlayerProfile> _fetchLiveProfile() async {
    final RiotSession? session = _sessions.session;
    if (session == null) throw const NotAuthenticatedException();

    // Independent calls; run them together to keep header latency down.
    final results = await (
      _api.fetchWallet(shard: session.shard, puuid: session.puuid),
      _api.fetchCompetitiveStanding(
        shard: session.shard,
        puuid: session.puuid,
      ),
    ).wait;
    final Wallet wallet = results.$1;
    final standing = results.$2;

    return PlayerProfile(
      puuid: session.puuid,
      gameName: session.gameName,
      tagLine: session.tagLine,
      wallet: wallet,
      competitiveTier: standing.tier,
      rankedRating: standing.rankedRating,
      updatedAt: DateTime.now(),
    );
  }

  PlayerProfile _buildDemoProfile() {
    final ({int rankedRating, int tier}) standing =
        _demo.buildCompetitiveStanding();
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
