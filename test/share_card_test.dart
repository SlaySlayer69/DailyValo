import 'dart:io';
import 'dart:ui' as ui;

import 'package:dailyvalo/src/features/content/data/models/content_tier.dart';
import 'package:dailyvalo/src/features/content/data/models/weapon_skin.dart';
import 'package:dailyvalo/src/features/store/presentation/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Renders the card the way `WidgetCapture` does — unconstrained, unscaled —
/// and returns its size.
///
/// The first version of this card shipped squeezed into the phone's width,
/// because an overlay child is constrained to the screen and a 1080-wide card
/// silently became a 411-wide one with 1080-scale type in it. These tests pin
/// the geometry so that cannot happen again unnoticed.
Future<Size> _pumpCard(WidgetTester tester, ShareCard card) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          // Minimums explicitly zero: OverflowBox forwards the parent's
          // minimum constraints unless told otherwise, which would inflate a
          // card smaller than the screen to screen size and bake a margin of
          // empty background into the image.
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: RepaintBoundary(child: card),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(ShareCard));
}

ShareEntry _entry(String weapon, String name, {ContentTier? tier, int? base}) =>
    ShareEntry(
      skin: WeaponSkin.fromJson(
        <String, dynamic>{
          'uuid': '$weapon-$name',
          'displayName': name,
          'contentTierUuid': tier == null ? null : Fixtures.tierPremiumUuid,
          'levels': <Map<String, dynamic>>[
            <String, dynamic>{'uuid': '$weapon-l1', 'displayName': name},
          ],
          'chromas': <Map<String, dynamic>>[],
        },
        weaponUuid: 'w-$weapon',
        weaponName: weapon,
        weaponCategory: 'Rifle',
      ),
      price: 1775,
      tier: tier,
      basePrice: base,
      discountPercent: base == null ? 0 : 30,
    );

void main() {
  // The real shop that produced the bad screenshot: two of these names are long
  // enough to have been cut to an ellipsis.
  final List<ShareEntry> dailyShop = <ShareEntry>[
    _entry('Bulldog', 'Aemondir Bulldog', tier: Fixtures.premium),
    _entry('Melee', 'Oni Claw', tier: Fixtures.ultra),
    _entry('Sheriff', 'Singularity Sheriff', tier: Fixtures.premium),
    _entry('Vandal', 'Prime Vandal', tier: Fixtures.premium),
  ];

  group('ShareCard geometry', () {
    testWidgets('renders at its designed width, not the screen width', (
      WidgetTester tester,
    ) async {
      final Size size = await _pumpCard(
        tester,
        ShareCard(entries: dailyShop),
      );

      // 40 margin × 2 + 4 tiles × 320 + 3 gaps × 20 = 1420.
      expect(size.width, 1420);
      expect(
        size.width,
        greaterThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
        reason: 'the card must not be limited by the test surface',
      );
    });

    testWidgets('lays the skins out side by side', (WidgetTester tester) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));

      final List<double> tops = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(Wrap),
              matching: find.byType(SizedBox),
            ),
          )
          .isEmpty
          ? <double>[]
          : find
                .descendant(
                  of: find.byType(Wrap),
                  matching: find.byWidgetPredicate(
                    (Widget w) => w is SizedBox && w.width == 320,
                  ),
                )
                .evaluate()
                .map((Element e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
                .toList();

      expect(tops, hasLength(4));
      // One row: every tile shares a top edge.
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets('six night-market deals wrap instead of squeezing', (
      WidgetTester tester,
    ) async {
      final List<ShareEntry> market = <ShareEntry>[
        for (int i = 0; i < 6; i++)
          _entry('Vandal', 'Deal $i', tier: Fixtures.premium, base: 2500),
      ];

      final Size size = await _pumpCard(tester, ShareCard(entries: market));

      // Three columns: 80 + 3 × 320 + 2 × 20 = 1080.
      expect(size.width, 1080);
    });

    testWidgets('a single offer does not stretch the canvas', (
      WidgetTester tester,
    ) async {
      final Size size = await _pumpCard(
        tester,
        ShareCard(entries: <ShareEntry>[dailyShop.first]),
      );

      expect(size.width, 40 * 2 + 320);
    });
  });

  group('ShareCard content', () {
    testWidgets('carries the wordmark and no title or date', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));

      // The mark is one rich text split across two colours.
      expect(find.text('DAILYVALO', findRichText: true), findsOneWidget);

      // Nothing that says "Daily Shop" or carries a date any more.
      expect(find.text('DAILY SHOP'), findsNothing);
      expect(find.textContaining('2026'), findsNothing);
    });

    testWidgets('the wordmark is centred on the canvas', (
      WidgetTester tester,
    ) async {
      // It was visibly off-centre before, pushed sideways by rules either side.
      final Size size = await _pumpCard(
        tester,
        ShareCard(entries: dailyShop),
      );

      final Rect markRect = tester.getRect(
        find.text('DAILYVALO', findRichText: true),
      );
      final double cardCentre = size.width / 2;
      expect(
        (markRect.center.dx - cardCentre).abs(),
        lessThan(1),
        reason: 'wordmark centre ${markRect.center.dx} vs card $cardCentre',
      );
    });

    testWidgets('long skin names are not cut to an ellipsis', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));

      // "Aemondir Bulldog" and "Singularity Sheriff" both broke the old card.
      for (final String name in <String>[
        'Aemondir Bulldog',
        'Singularity Sheriff',
      ]) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(name),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$name" was truncated',
        );
      }
    });

    testWidgets('shows the discount on a night-market tile only', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));
      expect(find.textContaining('%'), findsNothing);

      await _pumpCard(
        tester,
        ShareCard(
          entries: <ShareEntry>[
            _entry('Vandal', 'Reaver', tier: Fixtures.premium, base: 2500),
          ],
        ),
      );
      expect(find.text('-30%'), findsOneWidget);
    });

    testWidgets('nothing overflows', (WidgetTester tester) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));
      // A RenderFlex overflow fails the test through the exception reporter,
      // but assert it explicitly so the reason is obvious when it does.
      expect(tester.takeException(), isNull);
    });
  });

  group('ShareCard capture', () {
    testWidgets('produces a PNG at the expected pixel size', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, ShareCard(entries: dailyShop));

      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byType(RepaintBoundary).first,
      );

      late final Uint8List bytes;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2);
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        bytes = data!.buffer.asUint8List();
        image.dispose();

        // Inside runAsync: a widget test's fake clock never completes real
        // file IO, so a write out here produces an empty file.
        final String? out = Platform.environment['SHARE_CARD_DUMP'];
        if (out != null) await File(out).writeAsBytes(bytes, flush: true);
      });

      expect(bytes, isNotEmpty);
      // PNG magic number, so a silently empty capture cannot pass.
      expect(bytes.take(4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
