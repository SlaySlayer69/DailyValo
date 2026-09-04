import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../data/models/shop_sightings.dart';

/// The visual grammar of a drought, in one place.
///
/// Three states that have to be told apart at a glance: on offer now (accent,
/// the thing you act on), a dated absence (neutral), and never seen (warning —
/// not an error, but the one worth noticing).
extension _AvailabilityStyle on SkinAvailability {
  Color get color => switch (this) {
    InShopToday() => AppColors.accent,
    SeenBefore() => AppColors.textSecondary,
    NeverSeen() => AppColors.warning,
  };

  IconData get icon => switch (this) {
    InShopToday() => Icons.local_fire_department_rounded,
    SeenBefore() => Icons.history_rounded,
    NeverSeen() => Icons.help_outline_rounded,
  };
}

/// A one-line drought marker for a grid tile or a list row.
class DroughtChip extends StatelessWidget {
  const DroughtChip({required this.availability, super.key});

  final SkinAvailability availability;

  @override
  Widget build(BuildContext context) {
    final Color color = availability.color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(availability.icon, size: 11, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            availability.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 9.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The same marker with room for the whole sentence, for a list row.
class DroughtLine extends StatelessWidget {
  const DroughtLine({required this.availability, super.key});

  final SkinAvailability availability;

  @override
  Widget build(BuildContext context) {
    final Color color = availability.color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(availability.icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            availability.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The full statement, for the skin detail page.
///
/// Says what the app knows and — through [SkinAvailability.label] — how long it
/// has been in a position to know it, so a fresh install cannot imply that a
/// skin has been missing for years when it has been watching for a week.
class DroughtPanel extends StatelessWidget {
  const DroughtPanel({
    required this.availability,
    required this.isOwned,
    super.key,
  });

  final SkinAvailability availability;

  /// Shown alongside rather than instead: owning a skin does not stop it
  /// appearing in the shop, and "owned, last seen 200 days ago" is a real and
  /// interesting sentence.
  final bool isOwned;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = availability.color;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: availability is InShopToday
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(availability.icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('SHOP HISTORY', style: text.labelSmall),
                const SizedBox(height: 3),
                Text(
                  availability.label,
                  style: text.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(_explanation, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _explanation {
    final String owned = isOwned
        ? 'You already own it. '
        : '';

    return switch (availability) {
      InShopToday() =>
        '${owned}Riot publishes no shop history, so DailyValo records every '
            'rotation it sees on this device.',
      SeenBefore() =>
        '${owned}Counted from the rotations this device has seen — days the '
            'app never ran are not in it.',
      NeverSeen() =>
        '${owned}Riot publishes no shop history, so this only counts the days '
            'DailyValo has been watching this account.',
    };
  }
}
