import 'package:dailyvalo/src/core/constants/riot_constants.dart';
import 'package:dailyvalo/src/features/player/data/models/player_profile.dart';
import 'package:dailyvalo/src/features/store/data/models/competitive_standing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the two bugs that shipped in 1.2.0, both of which failed *silently*
/// — a wrong balance and a wrong rank are indistinguishable from real data.
void main() {
  group('Wallet currency identifiers', () {
    // Verified against valorant-api.com/v1/currencies. A typo here does not
    // throw: the wallet payload simply has no such key and the balance reads
    // as a plausible 0, which is exactly how the Radianite bug hid.
    test('match Riot\'s published currency UUIDs', () {
      expect(
        RiotConstants.currencyValorantPoints,
        '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741',
      );
      expect(
        RiotConstants.currencyRadianitePoints,
        'e59aa87c-4cbf-517a-5983-6e81511be9b7',
      );
      expect(
        RiotConstants.currencyKingdomCredits,
        '85ca954a-41f2-ce94-9b45-8ca3dd39a00d',
      );
    });

    test('are distinct and well-formed', () {
      final List<String> ids = <String>[
        RiotConstants.currencyValorantPoints,
        RiotConstants.currencyRadianitePoints,
        RiotConstants.currencyKingdomCredits,
      ];
      expect(ids.toSet(), hasLength(3));
      for (final String id in ids) {
        expect(
          RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id),
          isTrue,
          reason: '$id is not a well-formed UUID',
        );
      }
    });
  });

  group('CompetitiveStanding', () {
    test('separates "unranked" from "unknown"', () {
      const CompetitiveStanding unranked = CompetitiveStanding.unranked();
      expect(unranked.isUnranked, isTrue);
      expect(unranked.tier, 0);

      // Unknown is modelled by absence, not by a sentinel tier.
      const CompetitiveStanding? unknown = null;
      expect(unknown, isNull);
    });

    test('carries a real tier through', () {
      const CompetitiveStanding s = CompetitiveStanding(
        tier: 22,
        rankedRating: 47,
      );
      expect(s.isUnranked, isFalse);
      expect(s.tier, 22);
      expect(s.rankedRating, 47);
    });
  });

  group('PlayerProfile rank confidence', () {
    PlayerProfile build({required bool rankKnown, int tier = 0}) =>
        PlayerProfile(
          puuid: 'p',
          gameName: 'SlaySlayer',
          tagLine: '161',
          wallet: const Wallet(valorantPoints: 1265, radianitePoints: 40),
          competitiveTier: tier,
          rankedRating: 0,
          rankKnown: rankKnown,
          updatedAt: DateTime(2026, 8, 7),
        );

    test('defaults to known, so existing callers are unaffected', () {
      expect(
        PlayerProfile(
          puuid: 'p',
          gameName: 'g',
          tagLine: 't',
          wallet: Wallet.empty,
          competitiveTier: 0,
          rankedRating: 0,
          updatedAt: DateTime(2026),
        ).rankKnown,
        isTrue,
      );
    });

    test('round trips the flag through the cache', () {
      final PlayerProfile restored = PlayerProfile.fromJson(
        build(rankKnown: false).toJson(),
      );
      expect(restored.rankKnown, isFalse);
      expect(restored.wallet.radianitePoints, 40);
    });

    test('a profile cached before the flag existed is treated as known', () {
      final Map<String, dynamic> legacy = build(rankKnown: true).toJson()
        ..remove('rankKnown');
      expect(PlayerProfile.fromJson(legacy).rankKnown, isTrue);
    });
  });
}
