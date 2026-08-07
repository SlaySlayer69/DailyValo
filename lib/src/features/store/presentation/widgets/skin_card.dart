import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
import '../../../player/presentation/widgets/currency_chip.dart';

/// The wide skin card used by the shop, night market and wishlist.
///
/// One card type across three tabs, parameterised rather than copied — the
/// pricing block is the only thing that genuinely differs, so that is the only
/// thing the caller supplies.
class SkinCard extends StatelessWidget {
  const SkinCard({
    required this.skin,
    required this.tier,
    super.key,
    this.price,
    this.priceOverride,
    this.badge,
    this.isOwned = false,
    this.isWishlisted = false,
    this.onTap,
    this.onToggleWishlist,
    this.height = 132,
    this.dimmed = false,
  });

  final WeaponSkin skin;
  final ContentTier? tier;

  /// Price in VP. Omit to hide the price row entirely (Collection tab).
  final int? price;

  /// Replaces the default price row — used by the Night Market to show the
  /// struck-through original next to the discounted price.
  final Widget? priceOverride;

  /// Top-left pill, e.g. the discount percentage.
  final Widget? badge;

  final bool isOwned;
  final bool isWishlisted;

  final VoidCallback? onTap;
  final VoidCallback? onToggleWishlist;

  final double height;

  /// Renders at reduced opacity — used for unrevealed Night Market cards.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tier?.color ?? AppColors.borderStrong;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                AppColors.surface,
                Color.alphaBlend(
                  accent.withValues(alpha: 0.13),
                  AppColors.surface,
                ),
              ],
            ),
          ),
          child: Opacity(
            opacity: dimmed ? 0.55 : 1,
            child: Stack(
              children: <Widget>[
                // Artwork bleeds off the right edge, as it does in game.
                Positioned(
                  right: -8,
                  top: 0,
                  bottom: 0,
                  width: 210,
                  child: RemoteImage(
                    url: skin.artwork,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerRight,
                  ),
                ),
                // Keeps the text readable where it overlaps the artwork.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.card,
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const <double>[0.0, 0.55, 1.0],
                        colors: <Color>[
                          AppColors.surface,
                          AppColors.surface.withValues(alpha: 0.72),
                          AppColors.surface.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          ?badge,
                          if (badge != null) const SizedBox(width: 6),
                          TierBadge(tier: tier),
                          const Spacer(),
                          if (onToggleWishlist != null)
                            _WishlistHeart(
                              isActive: isWishlisted,
                              onPressed: onToggleWishlist!,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        skin.weaponName.toUpperCase(),
                        style: text.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 190,
                        child: Text(
                          skin.displayName,
                          style: text.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: <Widget>[
                          if (priceOverride != null)
                            priceOverride!
                          else if (price != null)
                            CurrencyAmount(amount: price!),
                          if (isOwned) ...<Widget>[
                            if (price != null || priceOverride != null)
                              const SizedBox(width: AppSpacing.sm),
                            const _OwnedTag(),
                          ],
                          if (skin.hasChromas) ...<Widget>[
                            const SizedBox(width: AppSpacing.sm),
                            _ChromaDots(chromas: skin.chromas),
                          ],
                        ],
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

class _WishlistHeart extends StatelessWidget {
  const _WishlistHeart({required this.isActive, required this.onPressed});

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minHeight: 34, minWidth: 34),
      tooltip: isActive ? 'Remove from wishlist' : 'Add to wishlist',
      icon: Icon(
        isActive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 20,
        color: isActive ? AppColors.accent : AppColors.textTertiary,
      ),
    );
  }
}

class _OwnedTag extends StatelessWidget {
  const _OwnedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.check_rounded,
            size: 11,
            color: AppColors.success,
          ),
          const SizedBox(width: 3),
          Text(
            'OWNED',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.success,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour dots hinting that the skin has variants, without opening it.
class _ChromaDots extends StatelessWidget {
  const _ChromaDots({required this.chromas});

  final List<SkinChroma> chromas;

  @override
  Widget build(BuildContext context) {
    final List<SkinChroma> shown = chromas.take(4).toList(growable: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final SkinChroma chroma in shown)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              height: 11,
              width: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceVariant,
                border: Border.all(color: AppColors.borderStrong, width: 0.8),
              ),
              clipBehavior: Clip.antiAlias,
              child: RemoteImage(
                url: chroma.swatch,
                fit: BoxFit.cover,
                fallbackIcon: Icons.circle,
              ),
            ),
          ),
      ],
    );
  }
}
