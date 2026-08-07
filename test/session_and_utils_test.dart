import 'dart:convert';

import 'package:dailyvalo/src/core/constants/riot_constants.dart';
import 'package:dailyvalo/src/core/utils/formatters.dart';
import 'package:dailyvalo/src/core/utils/jwt.dart';
import 'package:dailyvalo/src/features/auth/data/models/riot_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an unsigned JWT with the given payload. Enough for [Jwt], which only
/// reads claims and never verifies.
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg(<String, dynamic>{'alg': 'RS256'})}.${seg(payload)}.sig';
}

void main() {
  group('Jwt', () {
    test('reads the expiry claim', () {
      final DateTime expiry = DateTime.utc(2026, 8, 7, 13);
      final String token = _jwt(<String, dynamic>{
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      });

      expect(Jwt.expiry(token), expiry);
    });

    test('reads the live affinity from a PAS token', () {
      final String pas = _jwt(<String, dynamic>{
        'affinities': <String, dynamic>{'live': 'eu', 'pbe': 'na'},
      });

      expect(Jwt.liveAffinity(pas), 'eu');
    });

    test('returns null on garbage rather than throwing', () {
      expect(Jwt.decodePayload('not-a-jwt'), isNull);
      expect(Jwt.expiry('a.b'), isNull);
      expect(Jwt.liveAffinity(_jwt(<String, dynamic>{'sub': 'x'})), isNull);
    });
  });

  group('RiotSession', () {
    RiotSession build({required DateTime expiresAt}) => RiotSession(
      accessToken: 'access',
      idToken: 'id',
      entitlementsToken: 'ent',
      puuid: 'puuid-1',
      gameName: 'SlaySlayer',
      tagLine: '161',
      region: 'eu',
      shard: 'eu',
      expiresAt: expiresAt,
    );

    test('formats the Riot ID', () {
      expect(
        build(expiresAt: DateTime.now().toUtc()).riotId,
        'SlaySlayer#161',
      );
    });

    test('expires a minute early so in-flight requests do not race it', () {
      final DateTime almost = DateTime.now().toUtc().add(
        const Duration(seconds: 30),
      );
      expect(build(expiresAt: almost).isExpired, isTrue);

      final DateTime comfortable = DateTime.now().toUtc().add(
        const Duration(minutes: 10),
      );
      expect(build(expiresAt: comfortable).isExpired, isFalse);
    });

    test('round trips through JSON for secure storage', () {
      final RiotSession original = build(
        expiresAt: DateTime.utc(2026, 8, 7, 13),
      );
      final RiotSession restored = RiotSession.fromJson(original.toJson());

      expect(restored.puuid, original.puuid);
      expect(restored.shard, 'eu');
      expect(restored.expiresAt, original.expiresAt);
    });

    test('prefers the access token exp claim over expires_in', () {
      final DateTime exp = DateTime.utc(2026, 8, 7, 14);
      final RiotSession session = RiotSession.fromTokens(
        accessToken: _jwt(<String, dynamic>{
          'exp': exp.millisecondsSinceEpoch ~/ 1000,
        }),
        idToken: 'id',
        entitlementsToken: 'ent',
        puuid: 'p',
        gameName: 'g',
        tagLine: 't',
        region: 'br',
        expiresInSeconds: 60,
      );

      expect(session.expiresAt, exp);
      // br routes onto the na shard.
      expect(session.shard, 'na');
    });

    test('falls back to expires_in when the token carries no exp', () {
      final RiotSession session = RiotSession.fromTokens(
        accessToken: 'opaque-token',
        idToken: 'id',
        entitlementsToken: 'ent',
        puuid: 'p',
        gameName: 'g',
        tagLine: '',
        region: 'kr',
        expiresInSeconds: 3600,
      );

      expect(session.isExpired, isFalse);
      expect(session.riotId, 'g');
    });
  });

  group('Region routing', () {
    test('maps affinities onto PD shards', () {
      expect(RiotConstants.shardForRegion('na'), 'na');
      expect(RiotConstants.shardForRegion('latam'), 'na');
      expect(RiotConstants.shardForRegion('br'), 'na');
      expect(RiotConstants.shardForRegion('EU'), 'eu');
      expect(RiotConstants.shardForRegion('ap'), 'ap');
      expect(RiotConstants.shardForRegion('kr'), 'kr');
    });

    test('defaults unknown affinities to na rather than building a bad URL',
        () {
      expect(RiotConstants.shardForRegion('mars'), 'na');
    });

    test('builds PD urls from the shard', () {
      expect(
        RiotConstants.wallet('eu', 'p1'),
        'https://pd.eu.a.pvp.net/store/v1/wallet/p1',
      );
    });
  });

  group('Formatters', () {
    test('groups point values', () {
      expect(Formatters.points(1775), '1,775');
      expect(Formatters.points(875), '875');
    });

    test('renders countdowns, dropping empty leading units', () {
      expect(
        Formatters.duration(const Duration(hours: 13, minutes: 24, seconds: 9)),
        '13h 24m 09s',
      );
      expect(
        Formatters.duration(const Duration(minutes: 4, seconds: 5)),
        '04m 05s',
      );
      expect(
        Formatters.duration(const Duration(days: 2, hours: 3)),
        '2d 03h 00m',
      );
    });

    test('clamps negative durations to zero', () {
      expect(Formatters.duration(const Duration(seconds: -30)), '00m 00s');
    });

    test('strips Riot enum prefixes', () {
      expect(Formatters.enumTail('EEquippableCategory::Rifle'), 'Rifle');
      expect(Formatters.enumTail(null), '');
    });

    test('title-cases shouty rank names', () {
      expect(Formatters.titleCase('ASCENDANT 2'), 'Ascendant 2');
    });
  });
}
