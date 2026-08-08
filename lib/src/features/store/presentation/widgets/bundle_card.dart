import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/countdown.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../../data/models/shop.dart';

/// A Featured Bundle, rendered large.
///
/// Bundles are the one thing in the shop Riot actually art-directs — they ship
/// with full key art and are the most expensive thing on the page — so this is
/// the only card that gets a hero image rather than a cut-out on a gradient.
class BundleCard extends StatelessWidget {
  const BundleCard({
    required this.bundle,
    super.key,
    this.onExpired,
    this.onTap,
  });

  final BundleOffer bundle;

  /// Fired when the bundle's own countdown reaches zero.
  final VoidCallback? onExpired;

  /// Opens the bundle's contents.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: AppRadius.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 172,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      RemoteImage(
                        url: bundle.info?.artwork,
                        fit: BoxFit.cover,
                        fallbackIcon: Icons.inventory_2_outlined,
                      ),
                      // Keeps the name legible over whatever art Riot ships.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: <double>[0.35, 1.0],
                            colors: <Color>[
                              Color(0x00000000),
                              Color(0xE6000000),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'FEATURED BUNDLE',
                              style: text.labelSmall?.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bundle.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (bundle.isDiscounted)
                        Positioned(
                          top: AppSpacing.md,
                          right: AppSpacing.md,
                          child: _DiscountBadge(
                            percent: bundle.discountPercent,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: <Widget>[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              CurrencyAmount(
                                amount: bundle.price,
                                style: text.titleLarge,
                              ),
                              if (bundle.isDiscounted) ...<Widget>[
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  Formatters.points(bundle.basePrice),
                                  style: text.bodySmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bundle.itemCount == 0
                                ? 'Bundle'
                                : '${bundle.itemCount} items',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Bundles run on their own clock — days, not hours — so this
                      // is a separate countdown from the daily reset.
                      CountdownPill(
                        target: bundle.endsAt,
                        label: 'Leaves in',
                        icon: Icons.hourglass_bottom_rounded,
                        onElapsed: onExpired,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.discount,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        '-$percent%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.background,
          fontSize: 11,
        ),
      ),
    );
  }
}
