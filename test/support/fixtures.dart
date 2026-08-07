import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/content_tier.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';

/// Real UUIDs and shapes, trimmed to what the tests need.
abstract final class Fixtures {
  // Content tiers, as `valorant-api.com/v1/contenttiers` returns them.
  static const String tierUltraUuid = '411e4a55-4e59-7757-41f0-86a53f101bb5';
  static const String tierPremiumUuid = '60bca009-4182-7998-dee7-b8a2558dc369';

  static final ContentTier ultra = ContentTier.fromJson(
    const <String, dynamic>{
      'uuid': tierUltraUuid,
      'displayName': 'Ultra Edition',
      'devName': 'Ultra',
      'rank': 3,
      'highlightColor': 'f4d15aff',
      'displayIcon': 'https://media.valorant-api.com/contenttiers/ultra.png',
    },
  );

  static final ContentTier premium = ContentTier.fromJson(
    const <String, dynamic>{
      'uuid': tierPremiumUuid,
      'displayName': 'Premium Edition',
      'devName': 'Premium',
      'rank': 2,
      'highlightColor': 'd1548dff',
    },
  );

  // A skin with two levels and two chromas — the shape the shop returns.
  static const String primeVandalSkinUuid =
      '9f31a4e2-4c4d-b0ae-4e97-9b981e6b0d2c';
  static const String primeVandalLevel1Uuid =
      '2b8d2d3a-6cf1-4b02-9d6a-1c6f0f0f0001';
  static const String primeVandalLevel2Uuid =
      '2b8d2d3a-6cf1-4b02-9d6a-1c6f0f0f0002';

  static const String reaverSheriffSkinUuid =
      '77f9e2a9-6b8a-4f31-9e4d-52a1c2d3e4f5';
  static const String reaverSheriffLevel1Uuid =
      '88a1b2c3-d4e5-4f60-8a9b-0c1d2e3f4001';

  static const String glitchpopKnifeSkinUuid =
      'aa11bb22-cc33-4d44-9e55-f6a7b8c9d0e1';
  static const String glitchpopKnifeLevel1Uuid =
      'bb22cc33-dd44-4e55-8f66-a7b8c9d0e1f2';

  static WeaponSkin primeVandal() => WeaponSkin.fromJson(
    <String, dynamic>{
      'uuid': primeVandalSkinUuid,
      'displayName': 'Prime Vandal',
      'contentTierUuid': tierPremiumUuid,
      'displayIcon': 'https://media.valorant-api.com/prime-vandal.png',
      'wallpaper': 'https://media.valorant-api.com/prime-vandal-wall.png',
      'levels': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': primeVandalLevel1Uuid,
          'displayName': 'Prime Vandal',
          'levelItem': null,
        },
        <String, dynamic>{
          'uuid': primeVandalLevel2Uuid,
          'displayName': 'Prime Vandal Level 2',
          'levelItem': 'EEquippableSkinLevelItem::VFX',
          'streamedVideo': 'https://media.valorant-api.com/prime-vfx.mp4',
        },
      ],
      'chromas': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': 'c1',
          'displayName': 'Prime Vandal',
          'fullRender': 'https://media.valorant-api.com/prime-render.png',
        },
        <String, dynamic>{
          'uuid': 'c2',
          'displayName': 'Prime Vandal Level 1 Variant 2 Blue',
          'swatch': 'https://media.valorant-api.com/prime-blue.png',
        },
      ],
    },
    weaponUuid: 'w-vandal',
    weaponName: 'Vandal',
    weaponCategory: 'Rifle',
  );

  static WeaponSkin reaverSheriff() => WeaponSkin.fromJson(
    <String, dynamic>{
      'uuid': reaverSheriffSkinUuid,
      'displayName': 'Reaver Sheriff',
      'contentTierUuid': tierPremiumUuid,
      'displayIcon': 'https://media.valorant-api.com/reaver-sheriff.png',
      'levels': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': reaverSheriffLevel1Uuid,
          'displayName': 'Reaver Sheriff',
        },
      ],
      'chromas': <Map<String, dynamic>>[],
    },
    weaponUuid: 'w-sheriff',
    weaponName: 'Sheriff',
    weaponCategory: 'Sidearm',
  );

  static WeaponSkin glitchpopKnife() => WeaponSkin.fromJson(
    <String, dynamic>{
      'uuid': glitchpopKnifeSkinUuid,
      'displayName': 'Glitchpop Dagger',
      'contentTierUuid': tierUltraUuid,
      'displayIcon': 'https://media.valorant-api.com/glitchpop-dagger.png',
      'levels': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': glitchpopKnifeLevel1Uuid,
          'displayName': 'Glitchpop Dagger',
        },
      ],
      'chromas': <Map<String, dynamic>>[],
    },
    weaponUuid: 'w-melee',
    weaponName: 'Melee',
    weaponCategory: 'Melee',
  );

  /// A skin with no level clips but a filmed colour variant — the case that
  /// makes the chroma-video fallback observable.
  static WeaponSkin glitchpopKnifeWithChromaVideo() => WeaponSkin.fromJson(
    <String, dynamic>{
      'uuid': glitchpopKnifeSkinUuid,
      'displayName': 'Glitchpop Dagger',
      'contentTierUuid': tierUltraUuid,
      'levels': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': glitchpopKnifeLevel1Uuid,
          'displayName': 'Glitchpop Dagger',
        },
      ],
      'chromas': <Map<String, dynamic>>[
        <String, dynamic>{'uuid': 'gk-c1', 'displayName': 'Glitchpop Dagger'},
        <String, dynamic>{
          'uuid': 'gk-c2',
          'displayName': 'Glitchpop Dagger Variant 2 Cyan',
          'streamedVideo': 'https://media.valorant-api.com/gk-v2.mp4',
        },
      ],
    },
    weaponUuid: 'w-melee',
    weaponName: 'Melee',
    weaponCategory: 'Melee',
  );

  /// A standard-issue weapon: no content tier, never sold.
  static WeaponSkin standardPhantom() => WeaponSkin.fromJson(
    <String, dynamic>{
      'uuid': 'std-phantom',
      'displayName': 'Phantom',
      'levels': <Map<String, dynamic>>[
        <String, dynamic>{'uuid': 'std-phantom-l1', 'displayName': 'Phantom'},
      ],
      'chromas': <Map<String, dynamic>>[],
    },
    weaponUuid: 'w-phantom',
    weaponName: 'Phantom',
    weaponCategory: 'Rifle',
  );

  static ContentCatalog catalog() => ContentCatalog(
    skins: <WeaponSkin>[
      primeVandal(),
      reaverSheriff(),
      glitchpopKnife(),
      standardPhantom(),
    ],
    tiers: <String, ContentTier>{
      tierUltraUuid: ultra,
      tierPremiumUuid: premium,
    },
    competitiveTiers: <int, CompetitiveTier>{
      0: CompetitiveTier.unranked,
      22: const CompetitiveTier(
        tier: 22,
        tierName: 'ASCENDANT 2',
        divisionName: 'ASCENDANT',
        color: '17a68bff',
        smallIcon: 'https://media.valorant-api.com/asc2.png',
      ),
    },
    language: 'en-US',
    // Deliberately far in the past so staleness assertions are unambiguous.
    fetchedAt: DateTime(2025),
  );

  /// A storefront body in the shape Riot's `/store/v2` and `/store/v3` return.
  static Map<String, dynamic> storefrontJson({
    bool withNightMarket = true,
  }) => <String, dynamic>{
    'SkinsPanelLayout': <String, dynamic>{
      'SingleItemOffers': <String>[
        primeVandalLevel1Uuid,
        reaverSheriffLevel1Uuid,
        glitchpopKnifeLevel1Uuid,
      ],
      'SingleItemStoreOffers': <Map<String, dynamic>>[
        _storeOffer(primeVandalLevel1Uuid, 1775),
        _storeOffer(reaverSheriffLevel1Uuid, 1775),
        _storeOffer(glitchpopKnifeLevel1Uuid, 4950),
      ],
      'SingleItemOffersRemainingDurationInSeconds': 3600,
    },
    if (withNightMarket)
      'BonusStore': <String, dynamic>{
        'BonusStoreOffers': <Map<String, dynamic>>[
          <String, dynamic>{
            'BonusOfferID': 'bonus-1',
            'Offer': _storeOffer(primeVandalLevel1Uuid, 1775),
            'DiscountPercent': 30,
            'DiscountCosts': <String, dynamic>{
              '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': 1242,
            },
            'IsSeen': true,
          },
        ],
        'BonusStoreRemainingDurationInSeconds': 172800,
      },
  };

  static Map<String, dynamic> _storeOffer(String offerId, int vp) =>
      <String, dynamic>{
        'OfferID': offerId,
        'IsDirectPurchase': true,
        'Cost': <String, dynamic>{
          '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': vp,
        },
      };
}
