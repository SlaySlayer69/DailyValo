import 'package:dio/dio.dart';

import '../core/constants/storage_keys.dart';
import '../core/constants/valorant_api_constants.dart';
import '../core/network/client_version.dart';
import '../core/network/dio_factory.dart';
import '../core/network/riot_session_manager.dart';
import '../core/storage/local_store.dart';
import '../core/storage/secure_token_store.dart';
import '../core/utils/logger.dart';
import '../features/auth/data/datasources/riot_auth_api.dart';
import '../features/content/data/datasources/valorant_api_client.dart';
import '../features/content/data/repositories/content_repository.dart';
import '../features/player/data/repositories/player_repository.dart';
import '../features/store/data/datasources/riot_store_api.dart';
import '../features/store/data/repositories/store_repository.dart';
import '../features/wishlist/data/repositories/wishlist_repository.dart';
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
    required this.localStore,
    required this.secureStore,
    required this.clientVersion,
    required this.authApi,
    required this.sessions,
    required this.contentApi,
    required this.content,
    required this.storeApi,
    required this.store,
    required this.wishlist,
    required this.player,
    required this.notifications,
  });

  final LocalStore localStore;
  final SecureTokenStore secureStore;
  final ClientVersionHolder clientVersion;

  final RiotAuthApi authApi;
  final RiotSessionManager sessions;

  final ValorantApiClient contentApi;
  final ContentRepository content;

  final RiotStoreApi storeApi;
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
  static Future<AppDependencies> bootstrap({bool isBackground = false}) async {
    final LocalStore localStore = await LocalStore.init();
    final SecureTokenStore secureStore = SecureTokenStore();
    final ClientVersionHolder clientVersion = ClientVersionHolder.fromCache();

    final RiotAuthApi authApi = RiotAuthApi(secureStore: secureStore);

    // The session manager refreshes tokens through the auth API, but the auth
    // API knows nothing about sessions — the dependency only points one way.
    final RiotSessionManager sessions = RiotSessionManager(
      secureStore: secureStore,
      refresher: authApi.reauthenticate,
    );
    await sessions.restore();

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

    final WishlistRepository wishlist = WishlistRepository(store: localStore);
    final StoreRepository store = StoreRepository(
      api: storeApi,
      content: content,
      wishlist: wishlist,
      sessions: sessions,
      store: localStore,
    );
    final PlayerRepository player = PlayerRepository(
      api: storeApi,
      sessions: sessions,
      store: localStore,
      content: content,
    );

    final NotificationService notifications = NotificationService();
    await notifications.init();

    Log.d(
      'Bootstrap',
      'Graph ready (${isBackground ? 'background' : 'ui'}), '
          'signedIn=${sessions.isAuthenticated}',
    );

    return AppDependencies._(
      localStore: localStore,
      secureStore: secureStore,
      clientVersion: clientVersion,
      authApi: authApi,
      sessions: sessions,
      contentApi: contentApi,
      content: content,
      storeApi: storeApi,
      store: store,
      wishlist: wishlist,
      player: player,
      notifications: notifications,
    );
  }

  bool get isDemoMode => localStore.setting<bool>(SettingKeys.demoMode, false);

  /// True when there is something to sync: either a real session or demo mode.
  bool get canFetchShop => sessions.isAuthenticated || isDemoMode;
}
