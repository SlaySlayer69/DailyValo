import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/auth/data/models/riot_session.dart';
import '../errors/app_exception.dart';
import '../storage/local_store.dart';
import '../storage/secure_token_store.dart';
import '../utils/logger.dart';

/// Mints a brand-new token set from the stored RSO cookie.
///
/// Implemented by the auth data source; declared here so the network layer
/// does not have to depend on the auth feature.
typedef SessionRefresher = Future<RiotSession> Function(RiotSession current);

/// Single source of truth for "who is signed in".
///
/// Both the UI isolate and the WorkManager isolate build one of these. It owns
/// the in-memory session, persists it, and — importantly — serialises refreshes
/// so four parallel PD calls that all 401 at once trigger exactly one token
/// refresh instead of four.
class RiotSessionManager extends ChangeNotifier {
  RiotSessionManager({
    required SecureTokenStore secureStore,
    required SessionRefresher refresher,
  }) : _secureStore = secureStore,
       _refresher = refresher;

  final SecureTokenStore _secureStore;
  final SessionRefresher _refresher;

  RiotSession? _session;
  Future<RiotSession>? _inFlightRefresh;

  RiotSession? get session => _session;
  bool get isAuthenticated => _session != null;

  /// Restores a persisted session, if any. Does *not* refresh it — callers get
  /// a possibly-expired session and the interceptor handles renewal lazily.
  Future<RiotSession?> restore() async {
    final String? raw = await _secureStore.readSession();
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      _session = RiotSession.fromJson(decoded);
      notifyListeners();
      return _session;
    } on FormatException catch (e) {
      Log.e('Session', 'Stored session was corrupt; discarding', e);
      await _secureStore.clear();
      return null;
    }
  }

  Future<void> adopt(RiotSession session) async {
    _session = session;
    await _secureStore.writeSession(jsonEncode(session.toJson()));
    notifyListeners();
  }

  /// Returns a session guaranteed to be non-expired, refreshing if needed.
  Future<RiotSession> requireValidSession() async {
    final RiotSession? current = _session;
    if (current == null) throw const NotAuthenticatedException();
    if (!current.isExpired) return current;
    return refresh();
  }

  /// Forces a token refresh. Concurrent callers share one network round trip.
  Future<RiotSession> refresh() {
    final Future<RiotSession>? inFlight = _inFlightRefresh;
    if (inFlight != null) return inFlight;

    final Future<RiotSession> future = _doRefresh();
    _inFlightRefresh = future;
    return future.whenComplete(() => _inFlightRefresh = null);
  }

  Future<RiotSession> _doRefresh() async {
    final RiotSession? current = _session;
    if (current == null) throw const NotAuthenticatedException();
    try {
      final RiotSession renewed = await _refresher(current);
      await adopt(renewed);
      Log.d('Session', 'Refreshed tokens for ${renewed.riotId}');
      return renewed;
    } on AuthException catch (e) {
      // The cookie is dead — nothing short of a real sign-in will fix this.
      if (e.requiresReLogin) await signOut();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _session = null;
    await _secureStore.clear();
    if (LocalStore.isReady) await LocalStore.instance.clearUserData();
    notifyListeners();
  }
}
