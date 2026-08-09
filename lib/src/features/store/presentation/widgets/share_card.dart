import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../data/models/shop.dart';

/// One tile of a shareable image.
class ShareEntry {
  const ShareEntry({
    required this.skin,
    required this.price,
    this.tier,
    this.basePrice,
    this.discountPercent = 0,
  });

  factory ShareEntry.fromOffer(ShopOffer offer) => ShareEntry(
    skin: offer.skin,
    price: offer.price,
    tier: offer.tier,
  );

  factory ShareEntry.fromDeal(NightMarketDeal deal) => ShareEntry(
    skin: deal.skin,
    price: deal.price,
    tier: deal.tier,
    basePrice: deal.basePrice,
    discountPercent: deal.discountPercent,
  );

  final WeaponSkin skin;
  final int price;
  final ContentTier? tier;

  /// Set for Night Market tiles, where the discount is the whole point.
  final int? basePrice;
  final int discountPercent;

  bool get isDiscounted => basePrice != null && basePrice! > price;

  /// The cut-out render, which is what reads at tile size. The full wallpaper
  /// art is too busy once it is a few hundred pixels wide.
  String? get artwork => skin.displayIcon ?? skin.artwork;
}

/// The image people actually send.
///
/// Built as its own layout rather than screenshotting the tab: a screenshot
/// carries a status bar, a half-scrolled list and whatever font scale the
/// device is set to. This is a fixed canvas that looks the same from every
/// phone.
///
/// The skins sit side by side and the artwork gets most of each tile. A shop is
/// something you *look* at — the name and price are the caption, not the
/// subject — and a row of renders reads at a glance in a chat thread where a
/// stack of text rows does not.
///
/// Rendered off-screen and captured — see `WidgetCapture`.
class ShareCard extends StatelessWidget {
  const ShareCard({required this.entries, super.key});

  /// Tile edge length. The canvas is sized from this and the column count, so
  /// four offers and six night-market deals both come out proportionate
  /// instead of one being stretched to fit the other's frame.
  static const double _tile = 320;
  static const double _gap = 20;
  static const double _margin = 40;

  /// Four across for a daily shop; the night market's six wrap to three.
  static const int _maxColumns = 4;

  final List<ShareEntry> entries;

  int get _columns => entries.length <= _maxColumns
      ? entries.length.clamp(1, _maxColumns)
      : 3;

  double get _width => _margin * 2 + _columns * _tile + (_columns - 1) * _gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(_margin, 44, _margin, _margin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _Wordmark(),
          const SizedBox(height: 34),
          Wrap(
            spacing: _gap,
            runSpacing: _gap,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final ShareEntry entry in entries)
                SizedBox(
                  width: _tile,
                  child: _ShareTile(entry: entry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `DAILYVALO`, centred, with the accent on the second half — the same split as
/// the app icon's DV monogram.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    // No rules either side of it: they were what pushed the mark off-centre,
    // and the name alone is calmer.
    return const Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'DAILY',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          TextSpan(text: 'VALO', style: TextStyle(color: AppColors.accent)),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: 7,
        height: 1,
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({required this.entry});

  final ShareEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color accent = entry.tier?.color ?? AppColors.borderStrong;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.alphaBlend(accent.withValues(alpha: 0.22), AppColors.surface),
            AppColors.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // The artwork gets the tile. Everything below it is a caption.
          SizedBox(
            height: 150,
            child: RemoteImage(
              url: entry.artwork,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            entry.skin.weaponName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 5),
          // Two lines: skin names like "Singularity Sheriff" and "Aemondir
          // Bulldog" do not fit on one at this width, and cutting them to an
          // ellipsis was the single worst thing about the old card.
          SizedBox(
            height: 54,
            child: Text(
              entry.skin.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Price(entry: entry),
        ],
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.entry});

  final ShareEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${Formatters.points(entry.price)} VP',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (entry.isDiscounted) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Formatters.points(entry.basePrice!),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 15,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.textTertiary,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.discount,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '-${entry.discountPercent}%',
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
