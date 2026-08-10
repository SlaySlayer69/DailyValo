import 'package:dailyvalo/src/features/content/data/models/content_catalog.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('ContentCatalog', () {
    final ContentCatalog catalog = Fixtures.catalog();

    test('resolves a storefront offer id (a level uuid) to its skin', () {
      final WeaponSkin? skin = catalog.skinByOfferUuid(
        Fixtures.primeVandalLevel1Uuid,
      );
      expect(skin, isNotNull);
      expect(skin!.displayName, 'Prime Vandal');
      expect(skin.weaponName, 'Vandal');
    });

    test('resolves upper level uuids too, not just level 1', () {
      expect(
        catalog.skinByOfferUuid(Fixtures.primeVandalLevel2Uuid)?.uuid,
        Fixtures.primeVandalSkinUuid,
      );
    });

    test('returns null for an unknown uuid instead of throwing', () {
      expect(catalog.skinByOfferUuid('not-a-real-uuid'), isNull);
    });

    test('excludes standard-issue weapons from the purchasable pool', () {
      final List<String> names = catalog.purchasableSkins
          .map((WeaponSkin s) => s.displayName)
          .toList();

      expect(names, contains('Prime Vandal'));
      expect(names, isNot(contains('Phantom')));
    });

    test('joins skins to their rarity tier', () {
      final WeaponSkin knife = catalog.skinByUuid(
        Fixtures.glitchpopKnifeSkinUuid,
      )!;
      expect(catalog.tierOf(knife)?.devName, 'Ultra');
      expect(catalog.tierOf(Fixtures.standardPhantom()), isNull);
    });

    test('survives a cache round trip with its indexes intact', () {
      final ContentCatalog restored = ContentCatalog.fromJson(
        catalog.toJson(),
      );

      expect(restored.skins, hasLength(catalog.skins.length));
      expect(
        restored.skinByOfferUuid(Fixtures.reaverSheriffLevel1Uuid)?.weaponName,
        'Sheriff',
      );
      expect(restored.competitiveTier(22).tierName, 'ASCENDANT 2');
      expect(restored.competitiveTier(999).isUnranked, isTrue);
    });

    test('treats a catalogue older than a day as stale', () {
      expect(catalog.isStale, isTrue);

      final ContentCatalog fresh = ContentCatalog(
        skins: catalog.skins,
        tiers: catalog.tiers,
        competitiveTiers: catalog.competitiveTiers,
        language: 'en-US',
        fetchedAt: DateTime.now(),
      );
      expect(fresh.isStale, isFalse);
    });
  });

  group('WeaponSkin', () {
    test('builds the exact label the shop notification uses', () {
      expect(Fixtures.primeVandal().notificationLabel, 'Prime Vandal');
      // Melee is the case the weapon prefix was least useful for: "Melee:
      // Glitchpop Dagger" named the category, then the actual weapon.
      expect(Fixtures.glitchpopKnife().notificationLabel, 'Glitchpop Dagger');
    });

    test('prefers a chroma full render as card artwork', () {
      expect(
        Fixtures.primeVandal().artwork,
        'https://media.valorant-api.com/prime-render.png',
      );
    });

    test('falls back to displayIcon when no chroma has a render', () {
      expect(
        Fixtures.reaverSheriff().artwork,
        'https://media.valorant-api.com/reaver-sheriff.png',
      );
    });

    test('labels upgrade levels from the API classification', () {
      final List<SkinLevel> levels = Fixtures.primeVandal().levels;
      expect(levels.first.upgradeLabel, 'Base skin');
      expect(levels.last.upgradeLabel, 'Visual effects');
      expect(levels.last.hasVideo, isTrue);
    });

    test('shortens chroma names to just the variant', () {
      final SkinChroma blue = Fixtures.primeVandal().chromas.last;
      expect(blue.shortName('Prime Vandal'), 'Variant 2 Blue');
    });

    test('offerUuid is level 1, which is what the storefront sells', () {
      expect(Fixtures.primeVandal().offerUuid, Fixtures.primeVandalLevel1Uuid);
    });
  });

  group('Preview video selection', () {
    test('finds the first level clip the skin publishes', () {
      // Prime Vandal has no base clip but does have one on its VFX level.
      expect(
        Fixtures.primeVandal().previewVideoUrl,
        'https://media.valorant-api.com/prime-vfx.mp4',
      );
    });

    test('reports null when Riot publishes no clip at all', () {
      final WeaponSkin sheriff = Fixtures.reaverSheriff();
      expect(sheriff.previewVideoUrl, isNull);
      expect(sheriff.hasAnyPreviewVideo, isFalse);
    });

    test('a chroma-only clip still counts as previewable', () {
      // No level clips, but one variant is filmed.
      final WeaponSkin knife = Fixtures.glitchpopKnifeWithChromaVideo();
      expect(knife.previewVideoUrl, isNull);
      expect(knife.hasAnyPreviewVideo, isTrue);
      expect(knife.chromas.last.hasVideo, isTrue);
    });

    test('a level with no streamedVideo is not playable', () {
      final SkinLevel base = Fixtures.primeVandal().levels.first;
      expect(base.hasVideo, isFalse);
      expect(base.streamedVideo, isNull);
    });
  });
}
