import '../constants/riot_constants.dart';
import '../constants/storage_keys.dart';
import '../storage/local_store.dart';

/// Holds the `X-Riot-ClientVersion` string that PD endpoints require.
///
/// Riot rejects requests whose client version is too far behind live, so this
/// is refreshed from `valorant-api.com/v1/version` on every launch and cached
/// so a cold start (or the background isolate) still sends something sane.
class ClientVersionHolder {
  ClientVersionHolder({String? initial})
    : _value = initial ?? RiotConstants.fallbackClientVersion;

  String _value;

  String get value => _value;

  Future<void> update(String version) async {
    if (version.isEmpty || version == _value) return;
    _value = version;
    if (LocalStore.isReady) {
      await LocalStore.instance.writeCachedString(
        CacheKeys.clientVersion,
        version,
      );
    }
  }

  /// Seeds from cache. Call once, right after the local store is open.
  static ClientVersionHolder fromCache() {
    final String? cached = LocalStore.isReady
        ? LocalStore.instance.readCachedString(CacheKeys.clientVersion)
        : null;
    return ClientVersionHolder(initial: cached);
  }
}
