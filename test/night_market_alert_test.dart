import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/store/data/datasources/storefront_parser.dart';
import 'package:dailyvalo/src/features/store/data/models/shop.dart';
import 'package:dailyvalo/src/features/store/data/models/storefront_snapshot.dart';
import 'package:dailyvalo/src/services/background/shop_sync_service.dart';
import 'package:dailyvalo/src/services/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// The Night Market alert.
///
/// The one notification in the app that is genuinely time-limited: a market
/// runs for a few days, a few times a year, and being told about it on day
/// three is most of the way to not being told at all. So it is checked on every
/// background run rather than only on a run that finds the shop rotated — and
/// it has to fire exactly once per market, because a promo notification that
/// repeats daily for a week gets its channel muted, permanently.
void main() {
  final ContentCatalog catalog = Fixtures.catalog();

  Shop shopWith({required bool nightMarket, DateTime? now}) {
    final StorefrontSnapshot snapshot = StorefrontParser.parse(
      Fixtures.storefrontJson(withNightMarket: nightMarket),
      now: now ?? DateTime(2026, 8, 7, 12),
    );
    return Shop.resolve(snapshot: snapshot, catalog: catalog);
  }

  group('Marker', () {
    test('is null when no market is running', () {
      expect(
        ShopSyncService.nightMarketMarker(shopWith(nightMarket: false)),
        isNull,
      );
    });

    test('is the market\'s end date, not a flag', () {
      final Shop shop = shopWith(nightMarket: true);

      expect(
        ShopSyncService.nightMarketMarker(shop),
        shop.nightMarketEndsAt?.toIso8601String(),
      );
    });

    test('is unchanged while the same market runs', () {
      // Two background runs an hour apart. The remaining duration Riot reports
      // has ticked down, but the *end* is the same instant, so the marker has
      // to be identical or the alert repeats every hour all week.
      final StorefrontSnapshot first = StorefrontParser.parse(
        Fixtures.storefrontJson(),
        now: DateTime(2026, 8, 7, 12),
      );
      final StorefrontSnapshot second = StorefrontParser.parse(
        <String, dynamic>{
          ...Fixtures.storefrontJson(),
          'BonusStore': <String, dynamic>{
            ...Fixtures.storefrontJson()['BonusStore']! as Map<String, dynamic>,
            'BonusStoreRemainingDurationInSeconds': 172800 - 3600,
          },
        },
        now: DateTime(2026, 8, 7, 13),
      );

      expect(
        ShopSyncService.nightMarketMarker(
          Shop.resolve(snapshot: first, catalog: catalog),
        ),
        ShopSyncService.nightMarketMarker(
          Shop.resolve(snapshot: second, catalog: catalog),
        ),
      );
    });
  });

  group('Announcement', () {
    test('fires for a market nothing has been recorded for', () {
      expect(
        ShopSyncService.isNewNightMarket(announced: null, current: 'end-a'),
        isTrue,
      );
    });

    test('stays quiet for the market already announced', () {
      expect(
        ShopSyncService.isNewNightMarket(announced: 'end-a', current: 'end-a'),
        isFalse,
      );
    });

    test('fires again for a second market with a different end', () {
      // The case a boolean gets wrong: one market closes and another opens
      // between two runs, so "a market is running" never went false — but it
      // is a different market, and the user has not heard about it.
      expect(
        ShopSyncService.isNewNightMarket(announced: 'end-a', current: 'end-b'),
        isTrue,
      );
    });
  });

  group('Notification body', () {
    test('leads with the discount, which is what decides anything', () {
      expect(
        NotificationService.nightMarketBody(6, 47),
        'Night Market is open — 6 discounted skins, up to -47%',
      );
    });

    test('drops the discount rather than printing -0%', () {
      expect(
        NotificationService.nightMarketBody(6, 0),
        'Night Market is open — 6 discounted skins',
      );
    });

    test('agrees in number', () {
      expect(NotificationService.nightMarketBody(1, 20), contains('1 discounted skin,'));
    });
  });

  group('Notification ids', () {
    test('do not collide with the other kinds on the same account', () {
      final Set<int> ids = <int>{
        NotificationService.idFor(0, 1),
        NotificationService.idFor(0, 2),
        NotificationService.idFor(0, 3),
        NotificationService.idFor(0, 4),
      };

      expect(ids, hasLength(4));
    });

    test('do not collide across accounts', () {
      expect(
        NotificationService.idFor(0, 4),
        isNot(NotificationService.idFor(1, 4)),
      );
    });
  });
}
