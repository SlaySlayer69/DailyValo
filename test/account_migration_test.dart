import 'dart:convert';
import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/features/auth/data/account_registry.dart';
import 'package:dailyvalo/src/features/auth/data/models/account.dart';
import 'package:dailyvalo/src/features/auth/data/models/riot_session.dart';
import 'package:dailyvalo/src/features/wishlist/data/repositories/wishlist_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_secure_store.dart';

/// The upgrade from one account to many.
///
/// Every per-account key gained a puuid suffix, and the wishlist gained a
/// prefix. Left alone, all of that stays on disk under names nothing looks at
/// any more — so a device that upgrades without this looks exactly like a fresh
/// install: signed out, empty wishlist, empty collection. There is no error and
/// nothing to undo it with, which is why it is tested harder than the feature
/// it enables.
void main() {
  const String puuid = 'puuid-migrated';

  late Directory tempDir;
  late LocalStore store;
  late FakeSecureStore secure;

  Map<String, dynamic> legacySession() => <String, dynamic>{
    'accessToken': 'a',
    'idToken': 'b',
    'entitlementsToken': 'c',
    'puuid': puuid,
    'gameName': 'SlaySlayer',
    'tagLine': '161',
    'region': 'eu',
    'shard': 'eu',
    'expiresAt': DateTime(2030).toIso8601String(),
  };

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dailyvalo_migration');
    store = await LocalStore.initAt(tempDir.path);
    secure = FakeSecureStore();
  });

  tearDown(() async {
    await LocalStore.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seedLegacyInstall() async {
    secure.values[SecureKeys.legacySession] = jsonEncode(legacySession());
    secure.values[SecureKeys.legacySessionCookie] = 'the-ssid-cookie';
    // The pre-multi-account layout keyed by skin uuid alone.
    await store.putUnscopedWishlistEntry('skin-1', <String, dynamic>{
      'skinUuid': 'skin-1',
      'displayName': 'Prime Vandal',
      'addedAt': DateTime(2026).toIso8601String(),
    });
    await store.writeCached(CacheKeys.legacyShopSnapshot, <String, dynamic>{
      'x': 1,
    });
    await store.writeCached(CacheKeys.legacyNotifiedOfferIds, <String>['o1']);
    await store.writeCached(CacheKeys.legacyOwnedSkinLevels, <String>['s1']);
    await store.writeCached(CacheKeys.legacyPlayerProfile, <String, dynamic>{
      'gameName': 'SlaySlayer',
    });
  }

  group('Migrating a single-account install', () {
    test('registers the account that was signed in', () async {
      await seedLegacyInstall();

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      final AccountRegistry registry = AccountRegistry(store: store);
      final Account account = registry.all().single;
      expect(account.puuid, puuid);
      expect(account.gameName, 'SlaySlayer');
      expect(account.tagLine, '161');
      expect(registry.active?.puuid, puuid);
    });

    test('carries the session and the cookie across', () async {
      await seedLegacyInstall();

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      expect(secure.values[SecureKeys.session(puuid)], isNotNull);
      expect(secure.values[SecureKeys.sessionCookie(puuid)], 'the-ssid-cookie');
      // The cookie is what renews a session without the user; losing it here
      // would sign them out an hour later with no way to see why.
      expect(secure.values[SecureKeys.legacySession], isNull);
      expect(secure.values[SecureKeys.legacySessionCookie], isNull);
    });

    test('carries the wishlist across', () async {
      await seedLegacyInstall();

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      final WishlistRepository wishlist = WishlistRepository(
        store: store,
        accountId: puuid,
      );
      expect(wishlist.getAll(), hasLength(1));
      expect(wishlist.contains('skin-1'), isTrue);
    });

    test('carries the caches across under the new names', () async {
      await seedLegacyInstall();

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      expect(store.readCachedMap(CacheKeys.shopSnapshot(puuid)), isNotNull);
      expect(
        store.readCachedList(CacheKeys.notifiedOfferIds(puuid)),
        <String>['o1'],
      );
      expect(store.readCachedList(CacheKeys.ownedSkinLevels(puuid)), isNotNull);
      expect(store.readCachedMap(CacheKeys.playerProfile(puuid)), isNotNull);

      // Moved, not copied — a stale duplicate would come back as a second
      // account's data the day someone reads the old key by accident.
      expect(store.readCachedMap(CacheKeys.legacyShopSnapshot), isNull);
    });

    test('keeps the notification baseline, so no false rotation fires', () async {
      await seedLegacyInstall();

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      // Dropping it would make the first shop after the upgrade look brand
      // new, and announce offers the user has been looking at all day.
      expect(
        store.readCachedList(CacheKeys.notifiedOfferIds(puuid)),
        <String>['o1'],
      );
    });

    test('runs once', () async {
      await seedLegacyInstall();
      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      // A second pass finds no legacy session and must not disturb anything.
      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      expect(AccountRegistry(store: store).all(), hasLength(1));
    });

    test('a signed-out install migrates to nothing, without failing', () async {
      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      expect(AccountRegistry(store: store).all(), isEmpty);
      expect(store.setting<bool>(CacheKeys.accountMigrationDone, false), isTrue);
    });

    test('a corrupt session is not mistaken for an account', () async {
      secure.values[SecureKeys.legacySession] = 'not json at all';

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      expect(AccountRegistry(store: store).all(), isEmpty);
    });

    test('a failure leaves the flag unset, so the next launch retries', () async {
      await seedLegacyInstall();
      secure.failOnWrite = true;

      await AccountRegistry.migrateIfNeeded(store: store, secure: secure);

      // Half a migration is worse than none: retrying is how the wishlist
      // survives a keystore hiccup.
      expect(
        store.setting<bool>(CacheKeys.accountMigrationDone, false),
        isFalse,
      );
    });
  });

  group('The registry', () {
    test('gives each account a distinct slot', () async {
      final AccountRegistry registry = AccountRegistry(store: store);
      await registry.upsert(
        _session('p1', 'One'),
      );
      await registry.upsert(_session('p2', 'Two'));

      final List<Account> accounts = registry.all();
      expect(accounts, hasLength(2));
      expect(accounts.map((Account a) => a.slot).toSet(), hasLength(2));
    });

    test('signing into the same account again keeps its slot', () async {
      final AccountRegistry registry = AccountRegistry(store: store);
      await registry.upsert(_session('p1', 'One'));
      final int slot = registry.all().single.slot;

      await registry.upsert(_session('p1', 'Renamed'));

      final Account account = registry.all().single;
      // The slot addresses notifications Android may already be holding.
      expect(account.slot, slot);
      expect(account.gameName, 'Renamed');
      expect(registry.all(), hasLength(1));
    });

    test('reuses a slot freed by a sign-out', () async {
      final AccountRegistry registry = AccountRegistry(store: store);
      await registry.upsert(_session('p1', 'One'));
      await registry.upsert(_session('p2', 'Two'));
      await registry.remove('p1', secure);

      await registry.upsert(_session('p3', 'Three'));

      expect(registry.all().map((Account a) => a.slot).toSet(), hasLength(2));
    });

    test('falls back to another account when the active one goes', () async {
      final AccountRegistry registry = AccountRegistry(store: store);
      await registry.upsert(_session('p1', 'One'));
      await registry.upsert(_session('p2', 'Two'));
      expect(registry.active?.puuid, 'p2');

      await registry.remove('p2', secure);

      // Never a dangling pointer to an account that is gone — that would show
      // an empty shop with no way to say whose.
      expect(registry.active?.puuid, 'p1');
    });
  });
}

RiotSession _session(String puuid, String name) => RiotSession(
  accessToken: 'a',
  idToken: 'b',
  entitlementsToken: 'c',
  puuid: puuid,
  gameName: name,
  tagLine: 'EU',
  region: 'eu',
  shard: 'eu',
  expiresAt: DateTime(2030),
);
