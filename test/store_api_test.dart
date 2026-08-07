import 'dart:convert';
import 'dart:typed_data';

import 'package:dailyvalo/src/core/constants/riot_constants.dart';
import 'package:dailyvalo/src/features/player/data/models/player_profile.dart';
import 'package:dailyvalo/src/features/store/data/datasources/riot_store_api.dart';
import 'package:dailyvalo/src/features/store/data/models/competitive_standing.dart';
import 'package:dailyvalo/src/features/store/data/models/rank_attempt.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// One canned response, matched on a URL substring.
typedef Route = (String pattern, int status, Object body);

/// Serves canned responses so the API layer can be exercised without a network
/// or a Riot account.
///
/// Routes are an **ordered** list, first match wins — deliberately not a map
/// keyed by substring. The rank endpoints nest: `/mmr/v1/players/{puuid}` is a
/// prefix of that same player's `/competitiveupdates`. Unordered substring
/// matching therefore cannot express "the record 404s but match history
/// answers", which is exactly the case under test.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.routes);

  final List<Route> routes;

  /// Every URL requested, in order.
  final List<String> requested = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();
    requested.add(url);
    for (final Route route in routes) {
      if (url.contains(route.$1)) return _json(route.$3, route.$2);
    }
    return _json(const <String, dynamic>{}, 404);
  }

  static ResponseBody _json(Object body, int status) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
}

RiotStoreApi apiWith(StubAdapter adapter) =>
    RiotStoreApi(dio: Dio()..httpClientAdapter = adapter);

const String act = '4f0864e2-40af-28a4-de2c-0e9e64e75f23';

/// A rated match entry as `/competitiveupdates` returns it.
Map<String, dynamic> update(int tier, int rr) => <String, dynamic>{
  'TierAfterUpdate': tier,
  'RankedRatingAfterUpdate': rr,
};

Map<String, dynamic> matches(List<Map<String, dynamic>> list) =>
    <String, dynamic>{'Matches': list};

/// The full MMR record shape.
Map<String, dynamic> mmr({
  Map<String, dynamic>? seasonal,
  int latestTier = 0,
  int latestRr = 0,
}) => <String, dynamic>{
  'QueueSkills': <String, dynamic>{
    'competitive': <String, dynamic>{
      'SeasonalInfoBySeasonID': seasonal ?? <String, dynamic>{},
    },
  },
  'LatestCompetitiveUpdate': update(latestTier, latestRr),
};

void main() {
  group('fetchWallet', () {
    test('reads all three balances by their currency uuid', () async {
      final Wallet wallet = await apiWith(
        StubAdapter(<Route>[
          ('/store/v1/wallet/', 200, <String, dynamic>{
            'Balances': <String, dynamic>{
              RiotConstants.currencyValorantPoints: 1265,
              RiotConstants.currencyRadianitePoints: 250,
              RiotConstants.currencyKingdomCredits: 8150,
            },
          }),
        ]),
      ).fetchWallet(shard: 'eu', puuid: 'p');

      expect(wallet.valorantPoints, 1265);
      expect(wallet.radianitePoints, 250);
      expect(wallet.kingdomCredits, 8150);
    });

    test('a currency Riot omits reads as zero, not an error', () async {
      final Wallet wallet = await apiWith(
        StubAdapter(<Route>[
          ('/store/v1/wallet/', 200, <String, dynamic>{
            'Balances': <String, dynamic>{
              RiotConstants.currencyValorantPoints: 500,
            },
          }),
        ]),
      ).fetchWallet(shard: 'eu', puuid: 'p');

      expect(wallet.valorantPoints, 500);
      expect(wallet.radianitePoints, 0);
    });
  });

  group('fetchCompetitiveStanding', () {
    test('prefers the current act\'s seasonal entry', () async {
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          (
            '/mmr/v1/players/',
            200,
            mmr(
              seasonal: <String, dynamic>{
                act: <String, dynamic>{
                  'CompetitiveTier': 22,
                  'RankedRating': 47,
                },
                'older-act': <String, dynamic>{
                  'CompetitiveTier': 15,
                  'RankedRating': 90,
                },
              },
              latestTier: 15,
              latestRr: 90,
            ),
          ),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s?.tier, 22);
      expect(s?.rankedRating, 47);
    });

    test('falls back to the latest update when the act has no entry', () async {
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          ('/mmr/v1/players/', 200, mmr(latestTier: 18, latestRr: 33)),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s?.tier, 18);
      expect(s?.rankedRating, 33);
    });

    test('works without an act uuid at all', () async {
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          ('/mmr/v1/players/', 200, mmr(latestTier: 12, latestRr: 5)),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p');

      expect(s?.tier, 12);
    });

    test('falls back to match history when the MMR record 404s', () async {
      // The reported failure: MMR 404s while every other endpoint answers 200.
      final StubAdapter adapter = StubAdapter(<Route>[
        (
          'competitiveupdates',
          200,
          matches(<Map<String, dynamic>>[update(20, 61)]),
        ),
        ('/mmr/v1/players/', 404, const <String, dynamic>{}),
      ]);

      final CompetitiveStanding? s = await apiWith(
        adapter,
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s?.tier, 20);
      expect(s?.rankedRating, 61);
      expect(
        adapter.requested.any((String u) => u.contains('competitiveupdates')),
        isTrue,
      );
    });

    test('scans past unrated matches instead of taking the first', () async {
      // Placement and unrated results carry TierAfterUpdate 0. Reading only the
      // head of the list reported a ranked player as unranked.
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          (
            'competitiveupdates',
            200,
            matches(<Map<String, dynamic>>[
              update(0, 0),
              update(0, 0),
              update(21, 12),
            ]),
          ),
          ('/mmr/v1/players/', 404, const <String, dynamic>{}),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s?.tier, 21);
      expect(s?.rankedRating, 12);
    });

    test('asks for a window of matches, not just the latest one', () async {
      final StubAdapter adapter = StubAdapter(<Route>[
        ('competitiveupdates', 200, matches(const <Map<String, dynamic>>[])),
        ('/mmr/v1/players/', 404, const <String, dynamic>{}),
      ]);

      await apiWith(adapter).fetchCompetitiveStanding(shard: 'eu', puuid: 'p');

      expect(
        adapter.requested.any((String u) => u.contains('endIndex=20')),
        isTrue,
        reason: 'endIndex=1 let a single unrated match hide a real rank',
      );
    });

    test('falls back to the unfiltered queue when competitive is empty',
        () async {
      final StubAdapter adapter = StubAdapter(<Route>[
        // Ordered: the competitive-filtered request matches this first route.
        ('queue=competitive', 200, matches(const <Map<String, dynamic>>[])),
        (
          'competitiveupdates',
          200,
          matches(<Map<String, dynamic>>[update(17, 80)]),
        ),
        ('/mmr/v1/players/', 404, const <String, dynamic>{}),
      ]);

      final CompetitiveStanding? s = await apiWith(
        adapter,
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p');

      expect(s?.tier, 17);
    });

    test('walks back through acts when the current one has no standing',
        () async {
      // A player who has not placed this act still has a rank from the last.
      const String olderAct = 'older-act-uuid';
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          (
            '/mmr/v1/players/',
            200,
            mmr(
              seasonal: <String, dynamic>{
                olderAct: <String, dynamic>{
                  'CompetitiveTier': 19,
                  'RankedRating': 55,
                },
              },
            ),
          ),
        ]),
      ).fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        // Newest first: the current act is absent from the record.
        actUuids: const <String>[act, olderAct],
      );

      expect(s?.tier, 19);
      expect(s?.rankedRating, 55);
    });

    test('reports the payload shape when Matches is missing', () async {
      // Observed on a real account: HTTP 200 with no Matches key at all.
      // "no matches" and "unexpected shape" are different problems and the
      // diagnostics output has to tell them apart.
      final List<RankAttempt> attempts = <RankAttempt>[];

      await apiWith(
        StubAdapter(<Route>[
          ('competitiveupdates', 200, <String, dynamic>{
            'Version': 0,
            'Subject': 'p',
          }),
          ('/mmr/v1/players/', 404, const <String, dynamic>{}),
        ]),
      ).fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        attempts: attempts,
      );

      final RankAttempt history = attempts.firstWhere(
        (RankAttempt a) => a.source.contains('competitive'),
      );
      expect(history.note, contains('no Matches'));
      expect(history.note, contains('Version'));
      expect(history.note, contains('Subject'));
    });

    test('reports genuine unranked when every source answers empty', () async {
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          ('competitiveupdates', 200, matches(const <Map<String, dynamic>>[])),
          ('/mmr/v1/players/', 200, mmr()),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s, isNotNull, reason: 'Riot answered; this is a real unranked');
      expect(s!.isUnranked, isTrue);
    });

    test('records what each source did, for the diagnostics screen', () async {
      final List<RankAttempt> attempts = <RankAttempt>[];

      await apiWith(
        StubAdapter(<Route>[
          (
            'competitiveupdates',
            200,
            matches(<Map<String, dynamic>>[update(20, 61)]),
          ),
          ('/mmr/v1/players/', 404, const <String, dynamic>{}),
        ]),
      ).fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        actUuids: const <String>[act],
        attempts: attempts,
      );

      expect(attempts, hasLength(greaterThanOrEqualTo(2)));
      expect(attempts.first.source, contains('MMR record'));
      expect(attempts.first.ok, isFalse);
      expect(attempts.first.note, 'HTTP 404');
      expect(attempts.last.ok, isTrue);
    });

    test('returns null instead of throwing when every source fails', () async {
      // The contract the header depends on: rank is decoration, so an outage
      // must degrade to "unknown" rather than take the profile down with it.
      final CompetitiveStanding? s = await apiWith(
        StubAdapter(<Route>[
          ('competitiveupdates', 500, const <String, dynamic>{}),
          ('/mmr/v1/players/', 500, const <String, dynamic>{}),
        ]),
      ).fetchCompetitiveStanding(shard: 'eu', puuid: 'p', actUuids: const <String>[act]);

      expect(s, isNull);
    });
  });
}
