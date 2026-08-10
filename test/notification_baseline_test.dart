import 'dart:io';

import 'package:dailyvalo/src/core/constants/storage_keys.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The baseline that decides "have I already told the user about these four
/// offers?".
///
/// It used to be the shop cache itself, which cannot answer that question. Any
/// fetch overwrites that cache — including the one the Daily Shop tab makes the
/// moment you open the app — so opening the app shortly after a rotation wrote
/// the new offers into the baseline before anything had compared against them.
/// The rotation was consumed silently and its notification could never fire.
/// Opening the app at 02:00 to look at the new shop was, by itself, enough to
/// guarantee no notification that day.
///
/// These tests pin the separation, since the failure it prevents leaves no
/// trace: nothing arrives, and nothing says why.
void main() {
  late Directory tempDir;
  late LocalStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dailyvalo_baseline');
    store = await LocalStore.initAt(tempDir.path);
  });

  tearDown(() async {
    await LocalStore.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Set<String>? readBaseline() {
    final List<dynamic>? raw = store.readCachedList(
      CacheKeys.lastNotifiedOfferIds,
    );
    if (raw == null) return null;
    return raw.whereType<String>().toSet();
  }

  group('Notification baseline', () {
    test('is a different key from the shop cache', () {
      // If these ever collide the original bug is back, in full.
      expect(
        CacheKeys.lastNotifiedOfferIds,
        isNot(CacheKeys.lastShopSnapshot),
      );
    });

    test('survives a shop fetch overwriting the cache', () async {
      await store.writeCached(CacheKeys.lastNotifiedOfferIds, <String>[
        'offer-a',
        'offer-b',
      ]);

      // Exactly what `StoreRepository.getShop` does on every call, including
      // the one the UI makes when the tab opens.
      await store.writeCached(CacheKeys.lastShopSnapshot, <String, dynamic>{
        'dailyOffers': <Map<String, String>>[
          <String, String>{'offerId': 'offer-c'},
        ],
      });

      expect(readBaseline(), <String>{'offer-a', 'offer-b'});
    });

    test('round trips a set of offer ids', () async {
      await store.writeCached(CacheKeys.lastNotifiedOfferIds, <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(readBaseline(), <String>{'a', 'b', 'c', 'd'});
    });

    test('tells "never notified" apart from "notified about nothing"', () {
      // Null must stay silent — it is a fresh install, and announcing the shop
      // the user has been looking at all day is wrong. An empty set is a real
      // baseline and the next shop is genuinely new.
      expect(readBaseline(), isNull);
    });

    test('an empty recorded baseline reads back as empty, not null', () async {
      await store.writeCached(CacheKeys.lastNotifiedOfferIds, <String>[]);
      expect(readBaseline(), isNotNull);
      expect(readBaseline(), isEmpty);
    });

    test('a corrupt baseline reads as null rather than throwing', () async {
      await store.writeCachedString(CacheKeys.lastNotifiedOfferIds, 'not json');
      expect(readBaseline(), isNull);
    });

    test('non-string entries are dropped rather than crashing the sync', () async {
      await store.writeCached(CacheKeys.lastNotifiedOfferIds, <dynamic>[
        'a',
        42,
        null,
        'b',
      ]);
      expect(readBaseline(), <String>{'a', 'b'});
    });

    test('signing out clears it alongside the shop cache', () async {
      await store.writeCached(CacheKeys.lastNotifiedOfferIds, <String>['a']);
      await store.writeCached(CacheKeys.lastShopSnapshot, <String, dynamic>{});

      await store.clearUserData();

      // Left behind, the next account's first shop would be compared against
      // the previous account's offers and announced as a rotation.
      expect(readBaseline(), isNull);
      expect(store.readCachedMap(CacheKeys.lastShopSnapshot), isNull);
    });

    test('the wishlist is not collateral damage of a sign-out', () async {
      await store.putWishlistEntry('skin-1', <String, dynamic>{
        'skinUuid': 'skin-1',
      });

      await store.clearUserData();

      expect(store.isWishlisted('skin-1'), isTrue);
    });
  });
}
