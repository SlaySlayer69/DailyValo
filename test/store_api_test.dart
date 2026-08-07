import 'dart:convert';
import 'dart:typed_data';

import 'package:dailyvalo/src/core/constants/riot_constants.dart';
import 'package:dailyvalo/src/features/player/data/models/player_profile.dart';
import 'package:dailyvalo/src/features/store/data/datasources/riot_store_api.dart';
import 'package:dailyvalo/src/features/store/data/models/competitive_standing.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves canned responses per URL substring, so the API layer can be exercised
/// without a network or a Riot account.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.routes);

  /// URL substring -> (status, json body). A missing route yields 404.
  final Map<String, (int, Object)> routes;

  final List<String> requested = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    for (final MapEntry<String, (int, Object)> route in routes.entries) {
      if (options.uri.toString().contains(route.key)) {
        return ResponseBody.fromString(
          jsonEncode(route.value.$2),
          route.value.$1,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      }
    }
    return ResponseBody.fromString('{}', 404,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        });
  }
}

RiotStoreApi _apiWith(_StubAdapter adapter) {
  final Dio dio = Dio()..httpClientAdapter = adapter;
  return RiotStoreApi(dio: dio);
}

const String _act = '4f0864e2-40af-28a4-de2c-0e9e64e75f23';

void main() {
  group('fetchWallet', () {
    test('reads all three balances by their currency uuid', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/store/v1/wallet/': (200, <String, dynamic>{
            'Balances': <String, dynamic>{
              RiotConstants.currencyValorantPoints: 1265,
              RiotConstants.currencyRadianitePoints: 40,
              RiotConstants.currencyKingdomCredits: 8150,
            },
          }),
        }),
      );

      final Wallet wallet = await api.fetchWallet(shard: 'eu', puuid: 'p');
      expect(wallet.valorantPoints, 1265);
      expect(wallet.radianitePoints, 40);
      expect(wallet.kingdomCredits, 8150);
    });

    test('a currency Riot omits reads as zero, not an error', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/store/v1/wallet/': (200, <String, dynamic>{
            'Balances': <String, dynamic>{
              RiotConstants.currencyValorantPoints: 500,
            },
          }),
        }),
      );

      final Wallet wallet = await api.fetchWallet(shard: 'eu', puuid: 'p');
      expect(wallet.valorantPoints, 500);
      expect(wallet.radianitePoints, 0);
    });
  });

  group('fetchCompetitiveStanding', () {
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
      'LatestCompetitiveUpdate': <String, dynamic>{
        'TierAfterUpdate': latestTier,
        'RankedRatingAfterUpdate': latestRr,
      },
    };

    test('prefers the current act\'s seasonal entry', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/mmr/v1/players/': (
            200,
            mmr(
              seasonal: <String, dynamic>{
                _act: <String, dynamic>{
                  'CompetitiveTier': 22,
                  'RankedRating': 47,
                },
                'some-older-act': <String, dynamic>{
                  'CompetitiveTier': 15,
                  'RankedRating': 90,
                },
              },
              latestTier: 15,
              latestRr: 90,
            ),
          ),
        }),
      );

      final CompetitiveStanding? s = await api.fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        actUuid: _act,
      );
      expect(s, isNotNull);
      expect(s!.tier, 22);
      expect(s.rankedRating, 47);
    });

    test('falls back to the latest update when the act has no entry', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/mmr/v1/players/': (200, mmr(latestTier: 18, latestRr: 33)),
        }),
      );

      final CompetitiveStanding? s = await api.fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        actUuid: _act,
      );
      expect(s?.tier, 18);
      expect(s?.rankedRating, 33);
    });

    test('works without an act uuid at all', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/mmr/v1/players/': (200, mmr(latestTier: 12, latestRr: 5)),
        }),
      );

      expect(
        (await api.fetchCompetitiveStanding(shard: 'eu', puuid: 'p'))?.tier,
        12,
      );
    });

    test('reports genuine unranked when the record carries no rank', () async {
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/mmr/v1/players/': (200, mmr()),
        }),
      );

      final CompetitiveStanding? s = await api.fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        actUuid: _act,
      );
      expect(s, isNotNull, reason: 'Riot answered; this is a real unranked');
      expect(s!.isUnranked, isTrue);
    });

    test('falls back to /competitiveupdates when the MMR record 404s', () async {
      final _StubAdapter adapter = _StubAdapter(<String, (int, Object)>{
        'competitiveupdates': (200, <String, dynamic>{
          'Matches': <Map<String, dynamic>>[
            <String, dynamic>{
              'TierAfterUpdate': 20,
              'RankedRatingAfterUpdate': 61,
            },
          ],
        }),
      });
      final RiotStoreApi api = _apiWith(adapter);

      final CompetitiveStanding? s = await api.fetchCompetitiveStanding(
        shard: 'eu',
        puuid: 'p',
        actUuid: _act,
      );
      expect(s?.tier, 20);
      expect(
        adapter.requested.any((String u) => u.contains('competitiveupdates')),
        isTrue,
      );
    });

    test('returns null instead of throwing when every source fails', () async {
      // The contract the header depends on: rank is decoration, so an outage
      // must degrade to "unknown" rather than take the profile down with it.
      final RiotStoreApi api = _apiWith(
        _StubAdapter(<String, (int, Object)>{
          '/mmr/v1/players/': (500, <String, dynamic>{}),
          'competitiveupdates': (500, <String, dynamic>{}),
        }),
      );

      expect(
        await api.fetchCompetitiveStanding(
          shard: 'eu',
          puuid: 'p',
          actUuid: _act,
        ),
        isNull,
      );
    });
  });
}
