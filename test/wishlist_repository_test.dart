import 'dart:io';

import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/features/wishlist/data/models/wishlist_entry.dart';
import 'package:dailyvalo/src/features/wishlist/data/repositories/wishlist_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  late Directory tempDir;
  late LocalStore store;
  late WishlistRepository wishlist;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dailyvalo_test');
    store = await LocalStore.initAt(tempDir.path);
    wishlist = WishlistRepository(store: store);
  });

  tearDown(() async {
    await LocalStore.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('WishlistRepository', () {
    test('adds and removes by skin uuid', () async {
      expect(wishlist.getAll(), isEmpty);

      await wishlist.add(Fixtures.primeVandal());
      expect(wishlist.contains(Fixtures.primeVandalSkinUuid), isTrue);
      expect(wishlist.getAll().single.skinName, 'Prime Vandal');

      await wishlist.remove(Fixtures.primeVandalSkinUuid);
      expect(wishlist.getAll(), isEmpty);
    });

    test('toggle reports the resulting state', () async {
      expect(await wishlist.toggle(Fixtures.primeVandal()), isTrue);
      expect(await wishlist.toggle(Fixtures.primeVandal()), isFalse);
      expect(wishlist.getAll(), isEmpty);
    });

    test('restore puts a removed entry back where it was', () async {
      // The list is newest-first and an undo must not promote the restored
      // skin. The timestamp is explicit because two `add` calls in a row can
      // land in the same microsecond, which would make the ordering assertion
      // a race rather than a check.
      final WishlistEntry older = WishlistEntry(
        skinUuid: Fixtures.primeVandalSkinUuid,
        offerUuid: Fixtures.primeVandalLevel1Uuid,
        skinName: 'Prime Vandal',
        weaponName: 'Vandal',
        addedAt: DateTime(2026, 8, 1),
      );
      await wishlist.restore(older);
      await wishlist.add(Fixtures.glitchpopKnife());

      expect(wishlist.getAll().last.skinName, 'Prime Vandal');

      await wishlist.remove(older.skinUuid);
      expect(wishlist.getAll(), hasLength(1));

      await wishlist.restore(older);
      final List<WishlistEntry> restored = wishlist.getAll();
      expect(restored, hasLength(2));
      expect(
        restored.last.skinName,
        'Prime Vandal',
        reason: 'the original addedAt is kept, so it stays the older entry',
      );
      expect(restored.last.addedAt, older.addedAt);
      expect(restored.last.offerUuid, Fixtures.primeVandalLevel1Uuid);
    });

    test('restore is idempotent, so a double undo cannot duplicate', () async {
      await wishlist.add(Fixtures.primeVandal());
      final WishlistEntry entry = wishlist.getAll().single;

      await wishlist.remove(entry.skinUuid);
      await wishlist.restore(entry);
      await wishlist.restore(entry);

      expect(wishlist.getAll(), hasLength(1));
    });

    test('adding the same skin twice does not duplicate it', () async {
      await wishlist.add(Fixtures.primeVandal());
      await wishlist.add(Fixtures.primeVandal());
      expect(wishlist.getAll(), hasLength(1));
    });

    test('stores the level-1 uuid so shop matching is a set intersection',
        () async {
      await wishlist.add(Fixtures.primeVandal());
      expect(wishlist.offerUuids, <String>{Fixtures.primeVandalLevel1Uuid});
    });

    test('matches entries against the ids in a shop', () async {
      await wishlist.add(Fixtures.primeVandal());
      await wishlist.add(Fixtures.glitchpopKnife());

      final List<WishlistEntry> hits = wishlist.matching(<String>{
        Fixtures.glitchpopKnifeLevel1Uuid,
        Fixtures.reaverSheriffLevel1Uuid,
      });

      expect(hits, hasLength(1));
      expect(hits.single.label, 'Melee: Glitchpop Dagger');
    });

    test('reports no match when nothing wishlisted is on offer', () async {
      await wishlist.add(Fixtures.primeVandal());
      expect(
        wishlist.matching(<String>{Fixtures.reaverSheriffLevel1Uuid}),
        isEmpty,
      );
    });

    test('survives a reopen — the wishlist is the durable bit', () async {
      await wishlist.add(Fixtures.reaverSheriff());
      await LocalStore.reset();

      final LocalStore reopened = await LocalStore.initAt(tempDir.path);
      final WishlistRepository restored = WishlistRepository(
        store: reopened,
      );

      expect(restored.getAll().single.skinName, 'Reaver Sheriff');
    });
  });
}
