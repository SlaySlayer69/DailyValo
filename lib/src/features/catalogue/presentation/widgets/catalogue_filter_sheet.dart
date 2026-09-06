import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/skin_ordering.dart';
import '../../data/models/catalogue_query.dart';

/// The catalogue's filters, as a sheet.
///
/// A sheet rather than a row of controls on the page: there are four of them,
/// they are set once and then browsed against, and a permanent filter bar would
/// cost the grid a third of the screen to say "no filters" most of the time.
///
/// Edits are applied live to a local copy and returned on close, so the page
/// behind it only ever sees a whole query.
class CatalogueFilterSheet extends StatefulWidget {
  const CatalogueFilterSheet({
    required this.query,
    required this.tiers,
    required this.categories,
    super.key,
  });

  final CatalogueQuery query;

  /// Rarity key -> its colour, in rarest-first order, including the untiered
  /// bucket when the catalogue has one.
  final Map<String, Color> tiers;

  /// Weapon categories present in the catalogue.
  final List<String> categories;

  /// Returns the edited query, or null when dismissed unchanged.
  static Future<CatalogueQuery?> open(
    BuildContext context, {
    required CatalogueQuery query,
    required Map<String, Color> tiers,
    required List<String> categories,
  }) {
    return showModalBottomSheet<CatalogueQuery>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.backgroundElevated,
      builder: (BuildContext _) => CatalogueFilterSheet(
        query: query,
        tiers: tiers,
        categories: categories,
      ),
    );
  }

  @override
  State<CatalogueFilterSheet> createState() => _CatalogueFilterSheetState();
}

class _CatalogueFilterSheetState extends State<CatalogueFilterSheet> {
  late CatalogueQuery _query = widget.query;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('Filter', style: text.headlineSmall)),
                if (_query.activeFilterCount > 0)
                  TextButton(
                    onPressed: () => setState(() => _query = _query.cleared()),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('RARITY', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final MapEntry<String, Color> tier in widget.tiers.entries)
                  _Chip(
                    label: tier.key,
                    color: tier.value,
                    isSelected: _query.rarities.contains(tier.key),
                    onTap: () => setState(
                      () => _query = _query.copyWith(
                        rarities: _toggled(_query.rarities, tier.key),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            Text('WEAPON', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final String category in widget.categories)
                  _Chip(
                    label: category,
                    color: AppColors.borderStrong,
                    isSelected: _query.categories.contains(category),
                    onTap: () => setState(
                      () => _query = _query.copyWith(
                        categories: _toggled(_query.categories, category),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            Text('COLLECTION', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<OwnershipFilter>(
              segments: <ButtonSegment<OwnershipFilter>>[
                for (final OwnershipFilter option in OwnershipFilter.values)
                  ButtonSegment<OwnershipFilter>(
                    value: option,
                    label: Text(option.label),
                  ),
              ],
              selected: <OwnershipFilter>{_query.ownership},
              showSelectedIcon: false,
              onSelectionChanged: (Set<OwnershipFilter> picked) => setState(
                () => _query = _query.copyWith(ownership: picked.first),
              ),
            ),

            SwitchListTile.adaptive(
              value: _query.wishlistedOnly,
              onChanged: (bool value) => setState(
                () => _query = _query.copyWith(wishlistedOnly: value),
              ),
              title: const Text('Wishlisted only'),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_query),
              child: const Text('Show results'),
            ),
          ],
        ),
      ),
    );
  }

  static Set<String> _toggled(Set<String> current, String value) {
    final Set<String> next = <String>{...current};
    if (!next.remove(value)) next.add(value);
    return next;
  }
}

/// A selectable pill that carries its rarity's own colour when active.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isSelected ? 0.3 : 0.1),
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
            border: Border.all(
              color: color.withValues(alpha: isSelected ? 1 : 0.3),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isSelected ? AppColors.textPrimary : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The sort picker. Separate from the filters because it is one choice out of
/// five and reordering is not narrowing — mixing them would make "clear
/// filters" ambiguous about whether the order goes back too.
class CatalogueSortSheet extends StatelessWidget {
  const CatalogueSortSheet({required this.current, super.key});

  final CatalogueSort current;

  static Future<CatalogueSort?> open(
    BuildContext context, {
    required CatalogueSort current,
  }) {
    return showModalBottomSheet<CatalogueSort>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.backgroundElevated,
      builder: (BuildContext _) => CatalogueSortSheet(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Sort by',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final CatalogueSort option in CatalogueSort.values)
            ListTile(
              onTap: () => Navigator.of(context).pop(option),
              leading: Icon(
                option == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: option == current ? AppColors.accent : null,
              ),
              title: Text(option.label),
              subtitle: option == CatalogueSort.drought
                  ? const Text('Skins you have been waiting for longest')
                  : null,
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The rarity colours the filter sheet shows, rarest first.
Map<String, Color> rarityColoursOf(Iterable<ContentTier> tiers) {
  final Map<String, Color> byName = <String, Color>{
    for (final ContentTier tier in tiers) tier.devName: tier.color,
  };
  final List<String> ordered = byName.keys.toList()
    ..sort(
      (String a, String b) =>
          SkinOrdering.rarityIndex(a).compareTo(SkinOrdering.rarityIndex(b)),
    );
  return <String, Color>{
    for (final String name in ordered) name: byName[name]!,
  };
}
