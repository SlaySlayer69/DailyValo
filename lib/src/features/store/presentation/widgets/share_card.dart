import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../data/models/shop.dart';

/// One row of a shareable image.
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

  /// Set for Night Market rows, where the discount is the whole point.
  final int? basePrice;
  final int discountPercent;

  bool get isDiscounted => basePrice != null && basePrice! > price;
}

/// The image people actually send.
///
/// Built as its own layout rather than screenshotting the tab: a screenshot
/// carries a status bar, a nav bar, a half-scrolled list and whatever the
/// device's font scale happens to be. This is a fixed 1080-wide canvas that
/// looks the same from every phone, which is what makes it feel like a card
/// from the app rather than a photo of someone's screen.
///
/// Rendered off-screen and captured — see `WidgetCapture`.
class ShareCard extends StatelessWidget {
  const ShareCard({
    required this.title,
    required this.entries,
    super.key,
    this.subtitle,
    this.footnote,
  });

  /// The design canvas. Captured at 2× for a 2160px image, which is sharp on
  /// every phone and still small enough to send over a chat app.
  static const double width = 1080;

  final String title;
  final String? subtitle;
  final String? footnote;
  final List<ShareEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(56, 52, 56, 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Wordmark(),
          const SizedBox(height: 34),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 24,
                letterSpacing: 0.5,
              ),
            ),
          ],
          const SizedBox(height: 40),
          for (int i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 20),
            _ShareRow(entry: entries[i]),
          ],
          const SizedBox(height: 40),
          Text(
            footnote ?? 'dailyvalo',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 20,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// `DAILYVALO` centred, with the accent on the second half — the same split as
/// the app icon's DV monogram.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(width: 90, height: 2, color: AppColors.border),
        const SizedBox(width: 22),
        const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'DAILY',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              TextSpan(
                text: 'VALO',
                style: TextStyle(color: AppColors.accent),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(width: 22),
        Container(width: 90, height: 2, color: AppColors.border),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.entry});

  final ShareEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color accent = entry.tier?.color ?? AppColors.borderStrong;

    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 2),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color.alphaBlend(
              accent.withValues(alpha: 0.16),
              AppColors.surface,
            ),
            AppColors.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 22),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  entry.skin.weaponName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.skin.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                _Price(entry: entry),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 4,
            child: RemoteImage(
              url: entry.skin.displayIcon ?? entry.skin.artwork,
              fit: BoxFit.contain,
            ),
          ),
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
    return Row(
      children: <Widget>[
        Text(
          '${Formatters.points(entry.price)} VP',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (entry.isDiscounted) ...<Widget>[
          const SizedBox(width: 12),
          Text(
            Formatters.points(entry.basePrice!),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 20,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.textTertiary,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.discount,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '-${entry.discountPercent}%',
              style: const TextStyle(
                color: AppColors.background,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
