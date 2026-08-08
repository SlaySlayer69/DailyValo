import 'package:dailyvalo/src/features/content/data/models/accessory_item.dart';
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

  // --- Accessory store ----------------------------------------------------
  static const String sprayUuid = 'e1a2b3c4-1111-4222-8333-444455556666';
  static const String buddyUuid = 'f2b3c4d5-2222-4333-8444-555566667777';

  /// Buddies are granted by their *level* uuid, which is not the buddy uuid —
  /// the catalogue has to index both or the offer resolves to nothing.
  static const String buddyLevelUuid = 'f2b3c4d5-2222-4333-8444-555566667778';
  static const String playerCardUuid = 'a3c4d5e6-3333-4444-8555-666677778888';
  static const String playerTitleUuid = 'b4d5e6f7-4444-4555-8666-777788889999';

  static const AccessoryItem spray = AccessoryItem(
    uuid: sprayUuid,
    displayName: 'Good Game Spray',
    kind: AccessoryKind.spray,
    displayIcon: 'https://media.valorant-api.com/sprays/gg.png',
  );

  static const AccessoryItem buddy = AccessoryItem(
    uuid: buddyUuid,
    displayName: 'Polyfrog Buddy',
    kind: AccessoryKind.buddy,
    displayIcon: 'https://media.valorant-api.com/buddies/polyfrog.png',
  );

  static const AccessoryItem playerCard = AccessoryItem(
    uuid: playerCardUuid,
    displayName: 'Neptune Card',
    kind: AccessoryKind.playerCard,
    displayIcon: 'https://media.valorant-api.com/cards/neptune-small.png',
    wideArt: 'https://media.valorant-api.com/cards/neptune-wide.png',
  );

  static const AccessoryItem playerTitle = AccessoryItem(
    uuid: playerTitleUuid,
    displayName: 'Legend Title',
    kind: AccessoryKind.playerTitle,
    titleText: 'Legend',
  );

  /// Keyed the way `ValorantApiClient.fetchAccessories` keys it: every uuid
  /// that can appear as a reward, including buddy level uuids.
  static Map<String, AccessoryItem> accessories() => <String, AccessoryItem>{
    sprayUuid: spray,
    buddyUuid: buddy,
    buddyLevelUuid: buddy,
    playerCardUuid: playerCard,
    playerTitleUuid: playerTitle,
  };

  // --- Featured bundles ---------------------------------------------------
  static const String protocolBundleUuid =
      'c5e6f708-5555-4666-8777-88889999aaaa';

  static const BundleInfo protocolBundle = BundleInfo(
    uuid: protocolBundleUuid,
    displayName: 'Protocol 781-A',
    displayIcon: 'https://media.valorant-api.com/bundles/protocol.png',
    verticalPromoImage: 'https://media.valorant-api.com/bundles/protocol-v.png',
  );

  static Map<String, BundleInfo> bundles() => <String, BundleInfo>{
    protocolBundleUuid: protocolBundle,
  };

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
    accessories: accessories(),
    bundles: bundles(),
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
    bool withAccessories = true,
    bool withBundles = true,
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
    if (withAccessories)
      'AccessoryStore': <String, dynamic>{
        'AccessoryStoreOffers': <Map<String, dynamic>>[
          _accessoryOffer('acc-1', 325, <String>[sprayUuid]),
          // A buddy arrives as its level uuid, not its item uuid.
          _accessoryOffer('acc-2', 475, <String>[buddyLevelUuid]),
          _accessoryOffer('acc-3', 375, <String>[playerCardUuid]),
          _accessoryOffer('acc-4', 550, <String>[playerTitleUuid]),
          // Riot occasionally ships something the mirror has not indexed.
          _accessoryOffer('acc-5', 400, <String>['unknown-reward-uuid']),
        ],
        // A week out — deliberately far past the daily reset.
        'AccessoryStoreRemainingDurationInSeconds': 604800,
      },
    if (withBundles)
      'FeaturedBundle': <String, dynamic>{
        'Bundle': <String, dynamic>{'DataAssetID': protocolBundleUuid},
        'Bundles': <Map<String, dynamic>>[
          <String, dynamic>{
            'ID': 'storefront-instance-id',
            'DataAssetID': protocolBundleUuid,
            'CurrencyID': _vpUuid,
            'Items': <Map<String, dynamic>>[
              // A skin, granted by its level uuid, discounted.
              _bundleItem(
                itemTypeId: _skinLevelTypeId,
                itemId: primeVandalLevel1Uuid,
                basePrice: 2675,
                discountedPrice: 2005,
                discountPercent: 0.25,
              ),
              _bundleItem(
                itemTypeId: _skinLevelTypeId,
                itemId: glitchpopKnifeLevel1Uuid,
                basePrice: 4950,
                discountedPrice: 3712,
                discountPercent: 0.25,
              ),
              // The giveaway: a card at zero.
              _bundleItem(
                itemTypeId: AccessoryKind.playerCardTypeId,
                itemId: playerCardUuid,
                basePrice: 375,
                discountedPrice: 0,
                discountPercent: 1,
                isPromoItem: true,
              ),
              // Something the catalogue has never heard of.
              _bundleItem(
                itemTypeId: _skinLevelTypeId,
                itemId: 'shipped-in-todays-patch',
                basePrice: 1775,
                discountedPrice: 1331,
                discountPercent: 0.25,
              ),
            ],
            'DurationRemainingInSeconds': 259200,
            'TotalBaseCost': <String, dynamic>{_vpUuid: 8700},
            'TotalDiscountedCost': <String, dynamic>{_vpUuid: 6789},
            'TotalDiscountPercent': 0.2197,
            'WholesaleOnly': false,
          },
        ],
        'BundleRemainingDurationInSeconds': 259200,
      },
  };

  static Map<String, dynamic> _accessoryOffer(
    String offerId,
    int credits,
    List<String> rewardIds,
  ) => <String, dynamic>{
    'Offer': <String, dynamic>{
      'OfferID': offerId,
      'IsDirectPurchase': false,
      'Cost': <String, dynamic>{_kcUuid: credits},
      'Rewards': rewardIds
          .map(
            (String id) => <String, dynamic>{
              'ItemTypeID': 'ignored-by-the-parser',
              'ItemID': id,
              'Quantity': 1,
            },
          )
          .toList(),
    },
    'ContractID': 'y1s1-accessory-contract',
  };

  /// One entry of a bundle's `Items` array. Note the prices are plain numbers
  /// here, unlike the currency maps the rest of the storefront uses.
  static Map<String, dynamic> _bundleItem({
    required String itemTypeId,
    required String itemId,
    required int basePrice,
    required int discountedPrice,
    required num discountPercent,
    bool isPromoItem = false,
  }) => <String, dynamic>{
    'Item': <String, dynamic>{
      'ItemTypeID': itemTypeId,
      'ItemID': itemId,
      'Amount': 1,
    },
    'BasePrice': basePrice,
    'CurrencyID': _vpUuid,
    'DiscountPercent': discountPercent,
    'DiscountedPrice': discountedPrice,
    'IsPromoItem': isPromoItem,
  };

  static const String _skinLevelTypeId =
      'e7c63390-eda7-46e0-bb7a-a6abdacd2433';

  static const String _vpUuid = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  static const String _kcUuid = '85ca954a-41f2-ce94-9b45-8ca3dd39a00d';

  static Map<String, dynamic> _storeOffer(String offerId, int vp) =>
      <String, dynamic>{
        'OfferID': offerId,
        'IsDirectPurchase': true,
        'Cost': <String, dynamic>{
          '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741': vp,
        },
      };
}
