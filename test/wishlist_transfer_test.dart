import 'dart:convert';
import 'dart:io';

import 'package:dailyvalo/src/core/errors/app_exception.dart';
import 'package:dailyvalo/src/core/storage/local_store.dart';
import 'package:dailyvalo/src/features/wishlist/data/models/wishlist_entry.dart';
import 'package:dailyvalo/src/features/wishlist/data/repositories/wishlist_repository.dart';
import 'package:dailyvalo/src/features/wishlist/data/wishlist_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('WishlistTransfer format', () {
    test('round-trips a wishlist through its file format', () {
      final WishlistTransfer original = WishlistTransfer(
        entries: <WishlistEntry>[
          WishlistEntry.fromSkin(Fixtures.primeVandal()),
          WishlistEntry.fromSkin(Fixtures.glitchpopKnife()),
        ],
        exportedAt: DateTime(2026, 8, 9, 14, 30),
      );

      final WishlistTransfer restored = WishlistTransfer.decode(
        original.encode(),
      );

      expect(restored.entries, hasLength(2));
      expect(restored.entries.first.skinName, 'Prime Vandal');
      expect(
        restored.entries.first.offerUuid,
        Fixtures.primeVandalLevel1Uuid,
        reason: 'the level uuid is what makes shop matching work after import',
      );
      expect(restored.exportedAt, DateTime(2026, 8, 9, 14, 30));
    });

    test('an export carries everything needed to render without a catalogue', () {
      // The point of denormalising: an imported wishlist has to show names and
      // artwork on a device that has never fetched the catalogue.
      final Map<String, dynamic> json = jsonDecode(
        WishlistTransfer(
          entries: <WishlistEntry>[
            WishlistEntry.fromSkin(Fixtures.primeVandal()),
          ],
          exportedAt: DateTime(2026),
        ).encode(),
      ) as Map<String, dynamic>;

      final Map<String, dynamic> entry =
          (json['entries'] as List<dynamic>).first as Map<String, dynamic>;
      expect(entry['skinName'], 'Prime Vandal');
      expect(entry['weaponName'], 'Vandal');
      expect(entry['imageUrl'], isNotNull);
    });

    test('the filename is dated, because people export more than once', () {
      expect(
        WishlistTransfer(
          entries: const <WishlistEntry>[],
          exportedAt: DateTime(2026, 8, 9),
        ).fileName,
        'dailyvalo-wishlist-2026-08-09.json',
      );
    });
  });

  group('WishlistTransfer rejects bad input with something actionable', () {
    test('not JSON at all', () {
      expect(
        () => WishlistTransfer.decode('this is not json'),
        throwsA(
          isA<ParseException>().having(
            (ParseException e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('someone else\'s JSON file', () {
      expect(
        () => WishlistTransfer.decode('{"hello": "world"}'),
        throwsA(
          isA<ParseException>().having(
            (ParseException e) => e.message,
            'message',
            contains('not a DailyValo wishlist'),
          ),
        ),
      );
    });

    test('an export from a newer app version says so', () {
      // Silently dropping fields we do not understand would look like a
      // partial import with no explanation.
      final String source = jsonEncode(<String, dynamic>{
        'kind': WishlistTransfer.fileKind,
        'version': WishlistTransfer.formatVersion + 5,
        'entries': <dynamic>[],
      });

      expect(
        () => WishlistTransfer.decode(source),
        throwsA(
          isA<ParseException>().having(
            (ParseException e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('an empty export', () {
      final String source = jsonEncode(<String, dynamic>{
        'kind': WishlistTransfer.fileKind,
        'version': WishlistTransfer.formatVersion,
        'entries': <dynamic>[],
      });

      expect(
        () => WishlistTransfer.decode(source),
        throwsA(isA<ParseException>()),
      );
    });

    test('entries with no uuid are dropped, not imported as blanks', () {
      final String source = jsonEncode(<String, dynamic>{
        'kind': WishlistTransfer.fileKind,
        'version': WishlistTransfer.formatVersion,
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{'skinName': 'Corrupted row'},
          WishlistEntry.fromSkin(Fixtures.primeVandal()).toJson(),
        ],
      });

      final WishlistTransfer transfer = WishlistTransfer.decode(source);
      expect(transfer.entries, hasLength(1));
      expect(transfer.entries.single.skinName, 'Prime Vandal');
    });
  });

  group('Importing merges rather than replacing', () {
    late Directory tempDir;
    late LocalStore store;
    late WishlistRepository wishlist;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dailyvalo_transfer');
      store = await LocalStore.initAt(tempDir.path);
      wishlist = WishlistRepository(store: store);
    });

    tearDown(() async {
      await LocalStore.reset();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('adds what is new and keeps what was already there', () async {
      await wishlist.add(Fixtures.primeVandal());

      final ImportResult result = await wishlist.importEntries(<WishlistEntry>[
        WishlistEntry.fromSkin(Fixtures.primeVandal()),
        WishlistEntry.fromSkin(Fixtures.glitchpopKnife()),
      ]);

      expect(result.added, 1);
      expect(result.alreadyPresent, 1);
      expect(wishlist.getAll(), hasLength(2));
    });

    test('an existing entry keeps its original addedAt', () async {
      // Otherwise importing a backup would reshuffle a list the user ordered by
      // when they added things.
      final WishlistEntry old = WishlistEntry(
        skinUuid: Fixtures.primeVandalSkinUuid,
        offerUuid: Fixtures.primeVandalLevel1Uuid,
        skinName: 'Prime Vandal',
        weaponName: 'Vandal',
        addedAt: DateTime(2026),
      );
      await wishlist.restore(old);

      await wishlist.importEntries(<WishlistEntry>[
        WishlistEntry.fromSkin(Fixtures.primeVandal()),
      ]);

      expect(wishlist.getAll().single.addedAt, DateTime(2026));
    });

    test('importing the same file twice changes nothing the second time',
        () async {
      final List<WishlistEntry> entries = <WishlistEntry>[
        WishlistEntry.fromSkin(Fixtures.primeVandal()),
        WishlistEntry.fromSkin(Fixtures.reaverSheriff()),
      ];

      final ImportResult first = await wishlist.importEntries(entries);
      final ImportResult second = await wishlist.importEntries(entries);

      expect(first.added, 2);
      expect(second.added, 0);
      expect(second.alreadyPresent, 2);
      expect(wishlist.getAll(), hasLength(2));
    });

    test('the summary distinguishes "nothing to do" from "nothing happened"',
        () {
      expect(
        const ImportResult(added: 3, alreadyPresent: 0).summary,
        '3 skins added.',
      );
      expect(
        const ImportResult(added: 1, alreadyPresent: 2).summary,
        '1 skin added, 2 already there.',
      );
      expect(
        const ImportResult(added: 0, alreadyPresent: 4).summary,
        'All 4 skins were already on your wishlist.',
      );
    });

    test('an imported wishlist matches the shop straight away', () async {
      // The whole point of carrying offerUuid through the file.
      await wishlist.importEntries(<WishlistEntry>[
        WishlistEntry.fromSkin(Fixtures.primeVandal()),
      ]);

      expect(
        wishlist.matching(<String>{Fixtures.primeVandalLevel1Uuid}),
        hasLength(1),
      );
    });
  });
}
