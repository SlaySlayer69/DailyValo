import 'package:dailyvalo/src/features/store/data/models/shop_sightings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The drought counter.
///
/// Riot publishes no shop history, so every answer this gives is built from
/// what one device happened to observe. That is the whole risk in the feature:
/// a number that looks authoritative but is only as old as the install. The
/// tests below are mostly about keeping that distinction visible — "never seen"
/// has to carry how long "never" has been.
void main() {
  const String vandal = 'skin-vandal';
  const String sheriff = 'skin-sheriff';

  final DateTime day1 = DateTime(2026, 3, 1, 14, 30);
  final DateTime day2 = DateTime(2026, 3, 2, 9);
  final DateTime day10 = DateTime(2026, 3, 10, 2);

  group('ShopSightings', () {
    test('starts watching from today, not the epoch', () {
      final ShopSightings sightings = ShopSightings.startingAt(day1);

      expect(sightings.daysTracked(day1), 0);
      expect(sightings.lastSeen, isEmpty);
    });

    test('records a shop and dates it to the day, not the minute', () {
      final ShopSightings sightings = ShopSightings.startingAt(
        day1,
      ).record(<String>[vandal], day1);

      // Recorded at 14:30, asked at 02:00 nine days later: nine days, not eight
      // and a fraction rounded however `Duration` happens to truncate.
      expect(sightings.daysSince(vandal, day10), 9);
    });

    test('re-recording the same day changes nothing', () {
      final ShopSightings once = ShopSightings.startingAt(
        day1,
      ).record(<String>[vandal], day1);
      final ShopSightings twice = once.record(
        <String>[vandal],
        DateTime(2026, 3, 1, 23, 59),
      );

      expect(twice.daysSince(vandal, day2), once.daysSince(vandal, day2));
      expect(twice.lastSeen.length, 1);
    });

    test('a later sighting replaces the earlier one', () {
      final ShopSightings sightings = ShopSightings.startingAt(day1)
          .record(<String>[vandal], day1)
          .record(<String>[vandal], day10);

      expect(sightings.daysSince(vandal, day10), 0);
    });

    test('never returns a count for a skin it has not seen', () {
      final ShopSightings sightings = ShopSightings.startingAt(
        day1,
      ).record(<String>[vandal], day1);

      expect(sightings.daysSince(sheriff, day10), isNull);
    });

    test('recording is not destructive', () {
      final ShopSightings first = ShopSightings.startingAt(
        day1,
      ).record(<String>[vandal], day1);
      first.record(<String>[sheriff], day2);

      // `record` returns a new instance; the original must be untouched, since
      // the caller may still be rendering from it.
      expect(first.lastSeen.containsKey(sheriff), isFalse);
    });

    test('a sighting older than the tracking start moves the start back', () {
      // Restoring a backup, or a clock that jumped: the recorded day is the
      // evidence, and claiming to have tracked for -3 days is worse than
      // admitting the window is wider than expected.
      final ShopSightings sightings = ShopSightings.startingAt(
        day10,
      ).record(<String>[vandal], day1);

      expect(sightings.daysTracked(day10), 9);
    });

    test('round trips through JSON', () {
      final ShopSightings original = ShopSightings.startingAt(day1)
          .record(<String>[vandal], day1)
          .record(<String>[sheriff], day2);

      final ShopSightings? restored = ShopSightings.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.daysTracked(day10), original.daysTracked(day10));
      expect(restored.daysSince(vandal, day10), 9);
      expect(restored.daysSince(sheriff, day10), 8);
    });

    test('survives a corrupt entry rather than losing the whole record', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'trackedSince': day1.toIso8601String(),
        'lastSeen': <String, dynamic>{
          vandal: day1.toIso8601String(),
          sheriff: 'not a date',
          'nonsense': 42,
        },
      };

      final ShopSightings? restored = ShopSightings.fromJson(json);

      expect(restored, isNotNull);
      expect(restored!.daysSince(vandal, day10), 9);
      expect(restored.daysSince(sheriff, day10), isNull);
    });

    test('is unreadable without a tracking start', () {
      // Without it, everything it says about "never" is unfounded — better to
      // start over than to answer from a record that cannot qualify itself.
      expect(
        ShopSightings.fromJson(<String, dynamic>{
          'lastSeen': <String, dynamic>{vandal: day1.toIso8601String()},
        }),
        isNull,
      );
    });
  });

  group('SkinAvailability', () {
    ShopSightings seenOn(DateTime day) =>
        ShopSightings.startingAt(day1).record(<String>[vandal], day);

    SkinAvailability of({
      required Set<String> inShop,
      required ShopSightings sightings,
      DateTime? now,
    }) => SkinAvailability.of(
      skinUuid: vandal,
      inShopToday: inShop,
      sightings: sightings,
      now: now ?? day10,
    );

    test('today\'s shop wins over any recorded history', () {
      final SkinAvailability result = of(
        inShop: <String>{vandal},
        sightings: seenOn(day1),
      );

      expect(result, isA<InShopToday>());
      expect(result.label, 'In your shop today');
    });

    test('reports the days since the last sighting', () {
      final SkinAvailability result = of(
        inShop: const <String>{},
        sightings: seenOn(day1),
      );

      expect(result, isA<SeenBefore>());
      expect((result as SeenBefore).days, 9);
      expect(result.label, 'Last seen 9 days ago');
    });

    test('never-seen carries how long the device has been watching', () {
      // The distinction the whole model exists for: "never seen" on a device
      // tracking for nine days is a statement about the device, not the shop.
      final SkinAvailability result = of(
        inShop: const <String>{},
        sightings: ShopSightings.startingAt(day1),
      );

      expect(result, isA<NeverSeen>());
      expect((result as NeverSeen).daysTracked, 9);
      expect(result.label, contains('9 days'));
    });

    test('a fresh install does not claim a skin has been missing', () {
      final SkinAvailability result = of(
        inShop: const <String>{},
        sightings: ShopSightings.startingAt(day10),
      );

      expect(result.label, 'Not seen yet — tracking started today');
    });

    test('sorts never-seen above every dated drought', () {
      final int never = of(
        inShop: const <String>{},
        sightings: ShopSightings.startingAt(day1),
      ).droughtRank;
      final int longWait = of(
        inShop: const <String>{},
        sightings: seenOn(day1),
      ).droughtRank;
      final int inShop = of(
        inShop: <String>{vandal},
        sightings: seenOn(day1),
      ).droughtRank;

      expect(never, greaterThan(longWait));
      expect(longWait, greaterThan(inShop));
    });

    test('phrases one day in the singular', () {
      final SkinAvailability result = of(
        inShop: const <String>{},
        sightings: seenOn(DateTime(2026, 3, 9)),
      );

      expect(result.label, 'Last seen yesterday');
      expect(result.shortLabel, '1d ago');
    });
  });
}
