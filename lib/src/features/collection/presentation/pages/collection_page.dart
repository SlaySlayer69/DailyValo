import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
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
            : _CollectionGrid(
                skins: skins,
                catalog: catalog.valueOrNull,
              ),
      ),
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({required this.skins, required this.catalog});

  final List<WeaponSkin> skins;
  final ContentCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    // Skins arrive pre-sorted by rarity, so counting is a single pass.
    final Map<String, int> byTier = <String, int>{};
    for (final WeaponSkin skin in skins) {
      final String name = catalog?.tierOf(skin)?.devName ?? 'Other';
      byTier[name] = (byTier[name] ?? 0) + 1;
    }

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
                subtitle: '${skins.length} skins owned',
              ),
              const SizedBox(height: AppSpacing.md),
              _TierSummary(counts: byTier, catalog: catalog),
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
            itemCount: skins.length,
            itemBuilder: (BuildContext context, int index) {
              final WeaponSkin skin = skins[index];
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

class _TierSummary extends StatelessWidget {
  const _TierSummary({required this.counts, required this.catalog});

  final Map<String, int> counts;
  final ContentCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();

    // Order by the API's own rank so Exclusive reads first, Select last.
    final Map<String, ContentTier> byDevName = <String, ContentTier>{
      for (final ContentTier t in catalog?.tiers.values ?? const <ContentTier>[])
        t.devName: t,
    };
    final List<String> names = counts.keys.toList()
      ..sort(
        (String a, String b) => (byDevName[b]?.rank ?? -1).compareTo(
          byDevName[a]?.rank ?? -1,
        ),
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
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 9.5),
          ),
        ],
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
