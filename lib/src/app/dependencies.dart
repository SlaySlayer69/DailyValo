import 'package:dio/dio.dart';

import '../core/constants/storage_keys.dart';
import '../core/constants/valorant_api_constants.dart';
import '../core/network/client_version.dart';
import '../core/network/dio_factory.dart';
import '../core/network/riot_session_manager.dart';
import '../core/storage/local_store.dart';
import '../core/storage/secure_token_store.dart';
import '../core/utils/logger.dart';
import '../features/auth/data/account_registry.dart';
import '../features/auth/data/datasources/riot_auth_api.dart';
import '../features/auth/data/models/account.dart';
import '../features/auth/data/models/riot_session.dart';
import '../features/content/data/datasources/valorant_api_client.dart';
import '../features/content/data/repositories/content_repository.dart';
import '../features/player/data/repositories/player_repository.dart';
import '../features/store/data/datasources/riot_store_api.dart';
import '../features/store/data/repositories/store_repository.dart';
import '../features/wishlist/data/repositories/wishlist_repository.dart';
import '../services/logging/log_file.dart';
import '../services/notifications/notification_service.dart';

/// The application's object graph, built in one place.
///
/// This exists as a plain class rather than living inside Riverpod because the
/// WorkManager isolate needs the exact same graph and has no widget tree to
/// hang providers off. `bootstrap()` is called twice per device — once by
/// `main()`, once by the background worker — and both get identical wiring.
/// The Riverpod providers in `app/providers.dart` are a thin read-only view
/// over this.
class AppDependencies {
  AppDependencies._({
    required this.account,
    required this.accounts,
    required this.localStore,
    required this.secureStore,
    required this.clientVersion,
    required this.authApi,
    required this.sessions,
    required this.contentApi,
    required this.content,
    required this.storeApi,
    required this.gameDio,
    required this.store,
    required this.wishlist,
    required this.player,
    required this.notifications,
  });

  /// Whose app this graph is. Every per-account store below is scoped to it.
  final Account account;

  /// Device-wide: which accounts exist, and which one the UI shows.
  final AccountRegistry accounts;

  String get accountId => account.puuid;

  final LocalStore localStore;
  final SecureTokenStore secureStore;
  final ClientVersionHolder clientVersion;

  final RiotAuthApi authApi;
  final RiotSessionManager sessions;

  final ValorantApiClient contentApi;
  final ContentRepository content;

  final RiotStoreApi storeApi;

  /// The authenticated PD client. Exposed only so the diagnostics screen can
  /// probe endpoints directly and report the status code Riot returned —
  /// repositories deliberately swallow those to keep the UI calm.
  final Dio gameDio;

  final StoreRepository store;
  final WishlistRepository wishlist;
  final PlayerRepository player;

  final NotificationService notifications;

  /// Builds the graph.
  ///
  /// [isBackground] skips work that only makes sense with a UI attached — the
  /// notification tap handler, mainly — and keeps the worker's cold start
  /// short, since WorkManager gives it about ten minutes and Android will kill
  /// it well before that if it misbehaves.
  static Future<AppDependencies> bootstrap({
    bool isBackground = false,
    Account? forAccount,
  }) async {
    final LocalStore localStore = await LocalStore.init();
    await _startLogging(localStore, isBackground: isBackground);

    // Before anything reads an account-scoped key. An upgrade that skipped this
    // would look exactly like a fresh install — signed out, no wishlist — with
    // all of it still on disk under names nothing looks at any more.
    await AccountRegistry.migrateIfNeeded(
      store: localStore,
      secure: SecureTokenStore.unscoped(),
    );

    final AccountRegistry accounts = AccountRegistry(store: localStore);
    final Account account =
        forAccount ?? accounts.active ?? Account.signedOut;

    final SecureTokenStore secureStore = SecureTokenStore(
      accountId: account.puuid,
    );
    final ClientVersionHolder clientVersion = ClientVersionHolder.fromCache();

    final RiotAuthApi authApi = RiotAuthApi(secureStore: secureStore);

    // The session manager refreshes tokens through the auth API, but the auth
    // API knows nothing about sessions — the dependency only points one way.
    final RiotSessionManager sessions = RiotSessionManager(
      secureStore: secureStore,
      refresher: authApi.reauthenticate,
    );
    if (account.puuid.isNotEmpty) {
      await sessions.restore();
      await _recoverSessionFromCookie(sessions, authApi);
    }

    final Dio gameDio = DioFactory.createGameClient(
      sessionManager: sessions,
      clientVersion: clientVersion,
    );
    final RiotStoreApi storeApi = RiotStoreApi(dio: gameDio);

    final String language = localStore.setting<String>(
      SettingKeys.language,
      ValorantApiConstants.defaultLanguage,
    );
    final ValorantApiClient contentApi = ValorantApiClient(
      dio: DioFactory.createContentClient(),
      language: language,
    );
    final ContentRepository content = ContentRepository(
      client: contentApi,
      store: localStore,
      clientVersion: clientVersion,
    );

    final WishlistRepository wishlist = WishlistRepository(
      store: localStore,
      accountId: account.puuid,
    );
    final StoreRepository store = StoreRepository(
      api: storeApi,
      content: content,
      wishlist: wishlist,
      sessions: sessions,
      store: localStore,
      accountId: account.puuid,
    );
    final PlayerRepository player = PlayerRepository(
      api: storeApi,
      sessions: sessions,
      store: localStore,
      content: content,
      accountId: account.puuid,
    );

    final NotificationService notifications = NotificationService(
      account: account,
    );
    await notifications.init();

    Log.d(
      'Bootstrap',
      'Graph ready (${isBackground ? 'background' : 'ui'}) for '
          '${account.riotId}, signedIn=${sessions.isAuthenticated}',
    );

    return AppDependencies._(
      account: account,
      accounts: accounts,
      localStore: localStore,
      secureStore: secureStore,
      clientVersion: clientVersion,
      authApi: authApi,
      sessions: sessions,
      contentApi: contentApi,
      content: content,
      storeApi: storeApi,
      gameDio: gameDio,
      store: store,
      wishlist: wishlist,
      player: player,
      notifications: notifications,
    );
  }

  /// Points the logger at the file, if the user asked for one.
  ///
  /// First thing after storage and before anything that talks to the network,
  /// so a run that fails during start-up is still in the log. Both isolates
  /// call this; the setting is read from disk rather than passed in, because
  /// the worker has nobody to pass it.
  static Future<void> _startLogging(
    LocalStore store, {
    required bool isBackground,
  }) async {
    Log.isolate = isBackground ? 'bg' : 'ui';
    if (!store.setting<bool>(SettingKeys.verboseLogging, false)) {
      Log.toFile = false;
      return;
    }
    Log.toFile = await LogFile.open() != null;
    Log.d(
      'Boot',
      '--- ${isBackground ? 'background' : 'app'} start '
          '${DateTime.now().toIso8601String()} ---',
    );
  }

  /// Rebuilds a session from the stored cookie when there is none to restore.
  ///
  /// Without this the app drops to the login screen roughly an hour after every
  /// sign-in: the access token lapses, the renewal that would fix it needs a
  /// session that has already been discarded, and the user is left pressing a
  /// login button that signs them straight in without asking for anything.
  ///
  /// The cost of not doing it is not just that annoyance. A missing session
  /// means `canFetchShop` is false, so every background run skips, and no shop
  /// notification is ever scheduled — which is invisible, because nothing
  /// arrives to tell you nothing arrived.
  ///
  /// Failure is not fatal: it just means the login screen, which is where the
  /// user would have been anyway.
  static Future<void> _recoverSessionFromCookie(
    RiotSessionManager sessions,
    RiotAuthApi authApi,
  ) async {
    if (sessions.isAuthenticated) return;
    if (!await authApi.hasSessionCookie()) return;

    try {
      final RiotSession session = await authApi
          .signInWithStoredCookie()
          // Start-up cannot hang on Riot being slow; the login screen is a
          // perfectly good fallback.
          .timeout(const Duration(seconds: 12));
      await sessions.adopt(session);
      Log.d('Boot', 'Restored the session from the stored cookie');
    } on Object catch (e) {
      Log.d('Boot', 'Could not restore a session from the cookie: $e');
    }
  }

  bool get isDemoMode => localStore.setting<bool>(SettingKeys.demoMode, false);

  /// True when there is something to sync: either a real session or demo mode.
  bool get canFetchShop => sessions.isAuthenticated || isDemoMode;
}
