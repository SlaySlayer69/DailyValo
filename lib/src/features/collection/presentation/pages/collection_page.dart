import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/skin_ordering.dart';
import '../../../content/data/models/skin_pricing.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';

/// Tab 4 — every skin the account owns, grouped by rarity.
class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WeaponSkin>> collection = ref.watch(
      collectionProvider,
    );
    final AsyncValue<ContentCatalog> catalog = ref.watch(
      contentCatalogProvider,
    );

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        await ref.read(storeRepositoryProvider).refreshOwnedSkins();
        ref.invalidate(ownedSkinsProvider);
      },
      child: collection.when(
        loading: () => const _Scrollable(
          child: LoadingState(message: 'Loading your collection…'),
        ),
        error: (Object error, StackTrace _) => _Scrollable(
          child: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(ownedSkinsProvider),
          ),
        ),
        data: (List<WeaponSkin> skins) => skins.isEmpty
            ? const _Scrollable(
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No skins yet',
                  message:
                      'Once you own a premium skin it will appear here, with '
                      'its variants and upgrade levels.',
                ),
              )
            : _CollectionBody(
                skins: skins,
                catalog: catalog.valueOrNull,
              ),
      ),
    );
  }
}

/// The collection plus its rarity filter.
///
/// The filter lives here rather than in a provider because it is view state, not
/// app state: it should not survive a tab switch, and nothing outside this page
/// has any use for it.
class _CollectionBody extends StatefulWidget {
  const _CollectionBody({required this.skins, required this.catalog});

  final List<WeaponSkin> skins;
  final ContentCatalog? catalog;

  @override
  State<_CollectionBody> createState() => _CollectionBodyState();
}

class _CollectionBodyState extends State<_CollectionBody> {
  /// Selected tier `devName`s. Empty means "no filter", which is not the same
  /// as "nothing selected shows nothing" — deselecting the last chip has to
  /// bring the whole collection back, not empty the page.
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final ContentCatalog? catalog = widget.catalog;

    // Counted over the whole collection, never the filtered view, so the chips
    // keep saying how many you own while a filter is active.
    final Map<String, int> byTier = <String, int>{};
    for (final WeaponSkin skin in widget.skins) {
      final String name = catalog?.tierOf(skin)?.devName ?? 'Other';
      byTier[name] = (byTier[name] ?? 0) + 1;
    }

    // A tier that was selected and then vanished from the collection (a refresh
    // dropping a skin) would otherwise filter everything away invisibly.
    _selected.removeWhere((String name) => !byTier.containsKey(name));

    final List<WeaponSkin> visible = _selected.isEmpty
        ? widget.skins
        : widget.skins
              .where(
                (WeaponSkin s) => _selected.contains(
                  catalog?.tierOf(s)?.devName ?? 'Other',
                ),
              )
              .toList(growable: false);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              SectionHeader(
                title: 'Collection',
                subtitle: _selected.isEmpty
                    ? '${widget.skins.length} skins owned'
                    : '${visible.length} of ${widget.skins.length} skins',
                trailing: _selected.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('Clear'),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              _ValuePanel(
                value: CollectionValue.of(
                  visible,
                  (WeaponSkin s) => catalog?.tierOf(s),
                ),
                isFiltered: _selected.isNotEmpty,
              ),
              const SizedBox(height: AppSpacing.md),
              _TierFilter(
                counts: byTier,
                catalog: catalog,
                selected: _selected,
                onToggle: (String name) => setState(() {
                  if (!_selected.remove(name)) _selected.add(name);
                }),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          sliver: SliverGrid.builder(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.28,
                ),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int index) {
              final WeaponSkin skin = visible[index];
              return _CollectionTile(
                skin: skin,
                tier: catalog?.tierOf(skin),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// What the collection is worth at shop prices.
///
/// Deliberately labelled an estimate. Riot publishes no prices and no purchase
/// history, so this is what these skins *cost*, never what was paid for them —
/// see [SkinPricing].
class _ValuePanel extends StatelessWidget {
  const _ValuePanel({required this.value, required this.isFiltered});

  final CollectionValue value;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                isFiltered ? 'SELECTION VALUE' : 'COLLECTION VALUE',
                style: text.labelSmall,
              ),
              const Spacer(),
              Text(
                'ESTIMATE',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              CurrencyAmount(
                amount: value.totalVp,
                iconSize: 18,
                style: text.headlineMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _explanation,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  String get _explanation {
    final String base =
        'Full shop price of ${value.pricedCount} '
        '${value.pricedCount == 1 ? 'skin' : 'skins'} — not what you paid, '
        'since Riot exposes no purchase history and discounts leave no trace.';

    if (value.isComplete) return base;
    return '$base ${value.unpricedCount} '
        '${value.unpricedCount == 1 ? 'skin was' : 'skins were'} never sold '
        '(battlepass or event rewards) and ${value.unpricedCount == 1 ? 'is' : 'are'} '
        'left out.';
  }
}

/// The rarity chips: a count summary that doubles as a multi-select filter.
///
/// One control rather than two, because a separate row of filter buttons above
/// an identical row of counts would be the same information twice.
class _TierFilter extends StatelessWidget {
  const _TierFilter({
    required this.counts,
    required this.catalog,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, int> counts;
  final ContentCatalog? catalog;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();

    final Map<String, ContentTier> byDevName = <String, ContentTier>{
      for (final ContentTier t in catalog?.tiers.values ?? const <ContentTier>[])
        t.devName: t,
    };
    final List<String> names = counts.keys.toList()
      ..sort(
        (String a, String b) => SkinOrdering.rarityIndex(
          a,
        ).compareTo(SkinOrdering.rarityIndex(b)),
      );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final String name in names)
          _TierCount(
            label: name,
            count: counts[name] ?? 0,
            color: byDevName[name]?.color ?? AppColors.borderStrong,
            isSelected: selected.contains(name),
            onTap: () => onToggle(name),
          ),
      ],
    );
  }
}

class _TierCount extends StatelessWidget {
  const _TierCount({
    required this.label,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            // Selected chips carry their rarity's own colour at full strength;
            // unselected ones stay at the washed-out weight they had before the
            // filter existed, so the active set reads at a glance.
            color: color.withValues(alpha: isSelected ? 0.3 : 0.12),
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
            border: Border.all(
              color: color.withValues(alpha: isSelected ? 1 : 0.35),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: isSelected ? AppColors.textPrimary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.skin, required this.tier});

  final WeaponSkin skin;
  final ContentTier? tier;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tier?.color ?? AppColors.borderStrong;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: () => SkinDetailPage.open(
          context,
          skin: skin,
          tier: tier,
          isOwned: true,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color.alphaBlend(
                  accent.withValues(alpha: 0.12),
                  AppColors.surface,
                ),
                AppColors.surface,
              ],
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Align(
                alignment: Alignment.topRight,
                child: TierBadge(tier: tier, compact: true),
              ),
              Expanded(
                child: Center(
                  child: RemoteImage(
                    url: skin.displayIcon ?? skin.artwork,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(skin.weaponName.toUpperCase(), style: text.labelSmall),
              const SizedBox(height: 1),
              Text(
                skin.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
