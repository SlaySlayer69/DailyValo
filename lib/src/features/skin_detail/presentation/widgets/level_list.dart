import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/models/weapon_skin.dart';
import 'skin_video_sheet.dart';

/// The skin's upgrade ladder — what each Radianite level actually unlocks.
///
/// `levelItem` is the API's own classification (VFX, SoundEffects, Animation,
/// Finisher, …), so this list is exact rather than a guess from the level name.
/// Levels Riot publishes a clip for are tappable and open that clip: a still
/// image cannot show you what an animation or finisher does.
class LevelList extends StatelessWidget {
  const LevelList({required this.skin, required this.accent, super.key});

  final WeaponSkin skin;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final List<SkinLevel> levels = skin.levels;
    if (levels.isEmpty) return const SizedBox.shrink();

    final bool anyPlayable = levels.any((SkinLevel l) => l.hasVideo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Upgrades',
          subtitle: levels.length == 1
              ? 'No upgrade levels'
              : '${levels.length} levels',
        ),
        if (anyPlayable) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap a level to watch its preview',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < levels.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1, indent: 56),
                _LevelRow(
                  level: levels[i],
                  index: i,
                  accent: accent,
                  skinName: skin.displayName,
                  isFirst: i == 0,
                  isLast: i == levels.length - 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.index,
    required this.accent,
    required this.skinName,
    required this.isFirst,
    required this.isLast,
  });

  final SkinLevel level;
  final int index;
  final Color accent;
  final String skinName;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isBase = index == 0;

    // Only the top and bottom rows get rounded corners, so the ink splash
    // stays inside the card outline.
    final BorderRadius inkRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? AppRadius.md : 0),
      bottom: Radius.circular(isLast ? AppRadius.md : 0),
    );

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 30,
            width: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isBase
                  ? AppColors.surfaceVariant
                  : accent.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            child: Icon(
              _iconFor(level.levelItem),
              size: 15,
              color: isBase ? AppColors.textTertiary : accent,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Level ${index + 1}',
                  style: text.labelSmall?.copyWith(fontSize: 10),
                ),
                const SizedBox(height: 1),
                Text(
                  level.upgradeLabel,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (level.hasVideo)
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 19,
                color: accent,
              ),
            )
          else
            // Keeps every row the same height whether or not it has a clip.
            const SizedBox(height: 32, width: 32),
        ],
      ),
    );

    if (!level.hasVideo) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: inkRadius,
        onTap: () => SkinVideoSheet.open(
          context,
          videoUrl: level.streamedVideo!,
          title: 'Level ${index + 1} · ${level.upgradeLabel}',
          subtitle: skinName,
        ),
        child: row,
      ),
    );
  }

  static IconData _iconFor(String? levelItem) {
    final String tail = levelItem?.split('::').last ?? '';
    return switch (tail) {
      'VFX' => Icons.auto_awesome_rounded,
      'SoundEffects' => Icons.graphic_eq_rounded,
      'Animation' => Icons.animation_rounded,
      'Finisher' => Icons.military_tech_rounded,
      'Voiceover' => Icons.record_voice_over_rounded,
      'KillCounter' => Icons.tag_rounded,
      'InspectAndKill' => Icons.visibility_rounded,
      'Randomizer' => Icons.shuffle_rounded,
      'TopFrag' => Icons.emoji_events_rounded,
      _ => Icons.circle_outlined,
    };
  }
}
