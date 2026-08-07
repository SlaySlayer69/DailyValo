import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/models/weapon_skin.dart';

/// Horizontal swatch picker for a skin's colour variants.
///
/// Tapping a swatch swaps the hero render above, which is the only honest way
/// to preview a chroma — the swatch itself is a 32px circle and tells you very
/// little about what the gun looks like.
class ChromaSelector extends StatelessWidget {
  const ChromaSelector({
    required this.skin,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final WeaponSkin skin;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<SkinChroma> chromas = skin.chromas;
    if (chromas.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Variants',
          subtitle: '${chromas.length} chromas',
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chromas.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (BuildContext _, int _) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (BuildContext context, int index) {
              return _ChromaSwatch(
                chroma: chromas[index],
                skinName: skin.displayName,
                index: index,
                isSelected: index == selectedIndex,
                onTap: () => onSelected(index),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          chromas[selectedIndex].shortName(skin.displayName),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ChromaSwatch extends StatelessWidget {
  const _ChromaSwatch({
    required this.chroma,
    required this.skinName,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final SkinChroma chroma;
  final String skinName;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: chroma.shortName(skinName),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 52,
              width: 52,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.sm),
                ),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: RemoteImage(
                url: chroma.swatch ?? chroma.displayIcon,
                fit: BoxFit.cover,
                fallbackIcon: Icons.palette_outlined,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (chroma.hasVideo) ...<Widget>[
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 10,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(
                  index == 0 ? 'Base' : 'V${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textTertiary,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
