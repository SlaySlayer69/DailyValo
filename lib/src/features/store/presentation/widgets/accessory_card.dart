import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/accessory_item.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../../data/models/shop.dart';

/// One Accessory Store row.
///
/// Deliberately shorter and quieter than a skin card. Accessories are cheap
/// impulse items bought with Kingdom Credits, and giving them the same visual
/// weight as a 2,175 VP knife would misrepresent the shop.
class AccessoryCard extends StatelessWidget {
  const AccessoryCard({required this.offer, super.key});

  final AccessoryOffer offer;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AccessoryItem item = offer.primary;

    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          _Thumbnail(item: item),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  offer.subtitle.toUpperCase(),
                  style: text.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          CurrencyAmount(
            amount: offer.price,
            currency: Currency.kingdomCredits,
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Titles have no artwork at all, so they get their text rendered instead of
/// an empty placeholder box.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item});

  final AccessoryItem item;

  @override
  Widget build(BuildContext context) {
    // Player card art is a tall banner; everything else is roughly square.
    final bool isWide = item.kind == AccessoryKind.playerCard;

    return Container(
      height: 56,
      width: isWide ? 92 : 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: item.isTextOnly ? const EdgeInsets.all(6) : EdgeInsets.zero,
      alignment: Alignment.center,
      child: item.isTextOnly
          ? Text(
              item.titleText ?? item.displayName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          : RemoteImage(
              url: item.artwork,
              fit: isWide ? BoxFit.cover : BoxFit.contain,
              fallbackIcon: switch (item.kind) {
                AccessoryKind.spray => Icons.format_paint_outlined,
                AccessoryKind.buddy => Icons.card_giftcard_rounded,
                AccessoryKind.playerCard => Icons.badge_outlined,
                _ => Icons.category_outlined,
              },
            ),
    );
  }
}
