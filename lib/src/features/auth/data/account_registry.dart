import 'dart:convert';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/utils/logger.dart';
import 'models/account.dart';
import 'models/riot_session.dart';

/// Which accounts are signed in on this device, and which one the UI shows.
///
/// Device-wide, not account-scoped: the background worker reads it to find out
/// whose shops it has to check, and the settings sheet reads it to draw the
/// account switcher. It holds no credentials — those stay in the keystore,
/// keyed by puuid.
class AccountRegistry {
  AccountRegistry({required LocalStore store}) : _store = store;

  final LocalStore _store;

  List<Account> all() {
    final List<dynamic>? raw = _store.readCachedList(CacheKeys.accounts);
    if (raw == null) return const <Account>[];
    final List<Account> accounts = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => Account.fromJson(m.cast()))
        .whereType<Account>()
        .toList();
    // Oldest first, so the switcher does not reorder itself as accounts are
    // used — a list that moves under your thumb is worse than an arbitrary one.
    accounts.sort(
      (Account a, Account b) => (a.addedAt ?? DateTime(0)).compareTo(
        b.addedAt ?? DateTime(0),
      ),
    );
    return accounts;
  }

  bool get isEmpty => all().isEmpty;

  /// The account the UI is showing, or the first one if the stored choice has
  /// gone (removed on another screen, or never set).
  Account? get active {
    final List<Account> accounts = all();
    if (accounts.isEmpty) return null;
    final String? id = _store.readCachedString(CacheKeys.activeAccount);
    return accounts.firstWhere(
      (Account a) => a.puuid == id,
      orElse: () => accounts.first,
    );
  }

  Account? byId(String puuid) {
    for (final Account a in all()) {
      if (a.puuid == puuid) return a;
    }
    return null;
  }

  Future<void> setActive(String puuid) =>
      _store.writeCachedString(CacheKeys.activeAccount, puuid);

  /// Records a signed-in account, or refreshes the name of one already there.
  ///
  /// Signing into the same account twice must not create a second entry or
  /// hand it a new slot: the slot is what its queued notifications are
  /// addressed by.
  Future<Account> upsert(RiotSession session) async {
    final List<Account> accounts = all();
    final Account? existing = accounts
        .where((Account a) => a.puuid == session.puuid)
        .firstOrNull;

    final Account account = existing == null
        ? Account(
            puuid: session.puuid,
            gameName: session.gameName,
            tagLine: session.tagLine,
            slot: _freeSlot(accounts),
            addedAt: DateTime.now(),
          )
        : existing.copyWith(
            gameName: session.gameName,
            tagLine: session.tagLine,
          );

    final List<Account> next = <Account>[
      for (final Account a in accounts)
        if (a.puuid != account.puuid) a,
      account,
    ];
    await _write(next);
    await setActive(account.puuid);
    Log.d('Accounts', 'Signed in: ${account.riotId} (slot ${account.slot})');
    return account;
  }

  /// Signs one account out: credentials gone, cached server data gone.
  ///
  /// Its **wishlist stays**, keyed by the same puuid. Adding the account back
  /// picks it up again rather than starting from an empty list, which is the
  /// behaviour signing out has always had here and the one piece of data in the
  /// app nobody can reconstruct.
  Future<void> remove(String puuid, SecureTokenStore secure) async {
    await secure.clear();
    await _store.clearAccountCaches(puuid);
    await _write(all().where((Account a) => a.puuid != puuid).toList());

    final Account? next = active;
    if (next != null) await setActive(next.puuid);
    Log.d('Accounts', 'Removed $puuid');
  }

  /// The lowest number no current account holds.
  ///
  /// Reusing a gap keeps notification ids small and predictable; it is safe
  /// because [remove] cancels the departing account's notifications first.
  static int _freeSlot(List<Account> accounts) {
    final Set<int> taken = accounts.map((Account a) => a.slot).toSet();
    for (int i = 0; i < 64; i++) {
      if (!taken.contains(i)) return i;
    }
    return accounts.length;
  }

  Future<void> _write(List<Account> accounts) => _store.writeCached(
    CacheKeys.accounts,
    accounts.map((Account a) => a.toJson()).toList(growable: false),
  );

  /// Moves a pre-multi-account install onto the per-account layout.
  ///
  /// Runs once, before anything reads a scoped key. Without it an upgrade looks
  /// exactly like a fresh install: signed out, no wishlist, no collection —
  /// all of it still on disk under names nothing looks at any more.
  ///
  /// The old session is the only place the puuid can come from, so an install
  /// that was signed out has nothing to migrate and nothing to lose.
  static Future<void> migrateIfNeeded({
    required LocalStore store,
    required SecureTokenStore secure,
  }) async {
    if (store.setting<bool>(CacheKeys.accountMigrationDone, false)) return;

    try {
      final String? raw = await secure.readLegacySession();
      if (raw == null) {
        await store.putSetting(CacheKeys.accountMigrationDone, true);
        return;
      }

      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await store.putSetting(CacheKeys.accountMigrationDone, true);
        return;
      }
      final RiotSession session = RiotSession.fromJson(decoded);
      final String id = session.puuid;

      await secure.writeSessionFor(id, raw);
      final String? cookie = await secure.readLegacySessionCookie();
      if (cookie != null) await secure.writeSessionCookieFor(id, cookie);

      await store.moveCached(CacheKeys.legacyShopSnapshot, CacheKeys.shopSnapshot(id));
      await store.moveCached(
        CacheKeys.legacyNotifiedOfferIds,
        CacheKeys.notifiedOfferIds(id),
      );
      await store.moveCached(
        CacheKeys.legacyOwnedSkinLevels,
        CacheKeys.ownedSkinLevels(id),
      );
      await store.moveCached(
        CacheKeys.legacyPlayerProfile,
        CacheKeys.playerProfile(id),
      );
      await store.adoptUnscopedWishlist(id);

      await AccountRegistry(store: store).upsert(session);
      await secure.clearLegacy();
      await store.putSetting(CacheKeys.accountMigrationDone, true);
      Log.d('Accounts', 'Migrated ${session.riotId} to per-account storage');
    } on Object catch (e, st) {
      // Not marked done, so the next launch tries again. Losing a wishlist to a
      // half-finished migration is far worse than repeating it.
      Log.e('Accounts', 'Migration to per-account storage failed', e, st);
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
