import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/features/auth/data/models/account.dart';
import 'package:dailyvalo/src/features/wishlist/data/repositories/wishlist_repository.dart';
import 'package:dailyvalo/src/services/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Multi-account storage, notification addressing, and wishlist copying.
///
/// The thing these guard against is quiet cross-contamination: one account's
/// shop cached under another's name, one account's notification replacing
/// another's, one account's wishlist overwriting another's. None of those
/// announce themselves — they look like the app being wrong about your shop.
void main() {
  const String a = 'puuid-aaa';
  const String b = 'puuid-bbb';

  late Directory tempDir;
  late LocalStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dailyvalo_accounts');
    store = await LocalStore.initAt(tempDir.path);
  });

  tearDown(() async {
    await LocalStore.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('Per-account storage', () {
    test('two accounts keep separate wishlists', () async {
      final WishlistRepository first = WishlistRepository(
        store: store,
        accountId: a,
      );
      final WishlistRepository second = WishlistRepository(
        store: store,
        accountId: b,
      );

      await first.add(Fixtures.primeVandal());

      expect(first.contains(Fixtures.primeVandal().uuid), isTrue);
      expect(second.contains(Fixtures.primeVandal().uuid), isFalse);
      expect(second.getAll(), isEmpty);
    });

    test('removing from one leaves the other alone', () async {
      final WishlistRepository first = WishlistRepository(
        store: store,
        accountId: a,
      );
      final WishlistRepository second = WishlistRepository(
        store: store,
        accountId: b,
      );
      await first.add(Fixtures.primeVandal());
      await second.add(Fixtures.primeVandal());

      await first.remove(Fixtures.primeVandal().uuid);

      expect(first.getAll(), isEmpty);
      expect(second.getAll(), hasLength(1));
    });

    test('signing an account out keeps its wishlist', () async {
      final WishlistRepository first = WishlistRepository(
        store: store,
        accountId: a,
      );
      await first.add(Fixtures.primeVandal());
      await store.writeCached(CacheKeys.shopSnapshot(a), <String, dynamic>{});

      await store.clearAccountCaches(a);

      // The one thing here the user built by hand, and the one thing Riot
      // cannot hand back. Signing out has always kept it.
      expect(first.getAll(), hasLength(1));
      expect(store.readCachedMap(CacheKeys.shopSnapshot(a)), isNull);
    });
  });

  group('Copying a wishlist to another account', () {
    late WishlistRepository source;
    late WishlistRepository target;

    setUp(() {
      source = WishlistRepository(store: store, accountId: a);
      target = WishlistRepository(store: store, accountId: b);
    });

    test('adds what is missing', () async {
      await source.add(Fixtures.primeVandal());
      await source.add(Fixtures.glitchpopKnife());

      expect(await source.copyTo(b), 2);
      expect(target.getAll(), hasLength(2));
    });

    test('does not overwrite what is already there', () async {
      await source.add(Fixtures.primeVandal());
      await target.add(Fixtures.primeVandal());
      final DateTime before = target.getAll().single.addedAt;

      expect(await source.copyTo(b), 0);
      // Same entry, untouched — an overwrite would reset `addedAt` and
      // reshuffle the target's list for no reason.
      expect(target.getAll().single.addedAt, before);
    });

    test('reports only what was actually new', () async {
      await source.add(Fixtures.primeVandal());
      await source.add(Fixtures.glitchpopKnife());
      await target.add(Fixtures.primeVandal());

      // "Copied 2" when one was already there reads as though more happened
      // than did.
      expect(await source.copyTo(b), 1);
      expect(target.getAll(), hasLength(2));
    });

    test('leaves the source untouched', () async {
      await source.add(Fixtures.primeVandal());
      await source.copyTo(b);
      expect(source.getAll(), hasLength(1));
    });

    test('copying twice changes nothing the second time', () async {
      await source.add(Fixtures.primeVandal());
      expect(await source.copyTo(b), 1);
      expect(await source.copyTo(b), 0);
      expect(target.getAll(), hasLength(1));
    });

    test('copying to yourself is a no-op', () async {
      await source.add(Fixtures.primeVandal());
      expect(await source.copyTo(a), 0);
      expect(source.getAll(), hasLength(1));
    });
  });

  group('Notification addressing', () {
    Account at(int slot) => Account(
      puuid: 'p$slot',
      gameName: 'Player$slot',
      tagLine: 'EU',
      slot: slot,
      addedAt: DateTime(2026),
    );

    test('every account gets its own ids', () {
      final Set<int> ids = <int>{};
      for (int slot = 0; slot < 8; slot++) {
        final NotificationService service = NotificationService(
          account: at(slot),
        );
        ids.addAll(<int>[
          service.shopNotificationId,
          service.wishlistNotificationId,
          service.testNotificationId,
        ]);
      }
      // A collision means one account's digest silently replaces another's —
      // and on a shared id, cancelling one cancels both.
      expect(ids, hasLength(24));
    });

    test('the same account always gets the same ids', () {
      expect(
        NotificationService(account: at(3)).shopNotificationId,
        NotificationService(account: at(3)).shopNotificationId,
      );
    });

    test('ids come from the slot, not from list position', () {
      // Removing the first of three accounts must not hand its queued
      // notification to the second.
      expect(
        NotificationService(account: at(2)).shopNotificationId,
        NotificationService.idFor(2, 1),
      );
    });
  });

  group('Account', () {
    test('titles a notification with the game name, without the tag', () {
      final Account account = Account(
        puuid: 'p',
        gameName: 'SlaySlayer',
        tagLine: '161',
        slot: 0,
        addedAt: DateTime(2026),
      );
      expect(account.notificationTitle, 'SlaySlayer');
      expect(account.notificationTitle, isNot(contains('#')));
      // The tag is still what identifies the account everywhere it is picked.
      expect(account.riotId, 'SlaySlayer#161');
    });

    test('round trips through JSON, slot included', () {
      final Account account = Account(
        puuid: 'p',
        gameName: 'A',
        tagLine: 'B',
        slot: 4,
        addedAt: DateTime(2026, 5, 1),
      );
      final Account? back = Account.fromJson(account.toJson());
      expect(back?.puuid, 'p');
      expect(back?.slot, 4);
      expect(back?.riotId, 'A#B');
    });

    test('a record with no puuid is rejected rather than half-built', () {
      expect(Account.fromJson(<String, dynamic>{'gameName': 'A'}), isNull);
    });

    test('identity is the puuid, not the name', () {
      // Riot IDs can be changed, and two accounts can hold the same one at
      // different times.
      final Account renamed = Account(
        puuid: 'p',
        gameName: 'Before',
        tagLine: 'X',
        slot: 0,
        addedAt: DateTime(2026),
      ).copyWith(gameName: 'After');

      expect(renamed.puuid, 'p');
      expect(renamed.slot, 0);
      expect(
        renamed,
        Account(
          puuid: 'p',
          gameName: 'Anything',
          tagLine: 'Y',
          slot: 9,
          addedAt: DateTime(2020),
        ),
      );
    });
  });
}
