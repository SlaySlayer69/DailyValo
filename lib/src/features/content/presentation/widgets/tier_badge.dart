import 'package:flutter/material.dart';

import '../../../../core/widgets/remote_image.dart';
import '../../data/models/content_tier.dart';

/// The small rarity chip (`ULTRA`, `EXCLUSIVE`, ...) tinted with the tier's own
/// colour from the content API.
class TierBadge extends StatelessWidget {
  const TierBadge({required this.tier, super.key, this.compact = false});

  final ContentTier? tier;

  /// Icon-only, for dense grids.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ContentTier? t = tier;
    if (t == null) return const SizedBox.shrink();

    final Color color = t.color;

    if (compact) {
      return Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        padding: const EdgeInsets.all(2),
        child: RemoteImage(url: t.displayIcon, fallbackIcon: Icons.star_border),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (t.displayIcon != null)
            SizedBox(
              height: 12,
              width: 12,
              child: RemoteImage(url: t.displayIcon),
            ),
          if (t.displayIcon != null) const SizedBox(width: 5),
          Text(
            t.devName.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 9.5,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
