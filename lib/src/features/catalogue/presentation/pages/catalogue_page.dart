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
import '../../../content/data/models/weapon_skin.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';
import '../../../store/data/models/shop_sightings.dart';
import '../../../store/presentation/widgets/drought_indicator.dart';
import '../../../wishlist/data/models/wishlist_entry.dart';
import '../../data/models/catalogue_query.dart';
import '../widgets/catalogue_filter_sheet.dart';

/// Every skin Riot has ever sold, searchable.
///
/// The other four tabs each answer a question about *your* account — what is on
/// offer, what you are waiting for, what you own. This one is the catalogue
/// itself, and it is where the drought counter earns its keep: sorted by
/// longest unseen, it is a list of what your shop has been withholding.
class CataloguePage extends ConsumerStatefulWidget {
  const CataloguePage({super.key});

  @override
  ConsumerState<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends ConsumerState<CataloguePage> {
  final TextEditingController _search = TextEditingController();

  /// View state, not app state: a filter should not survive a tab switch, and
  /// nothing outside this page has any use for it.
  CatalogueQuery _query = const CatalogueQuery();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ContentCatalog> catalog = ref.watch(contentCatalogProvider);

    return catalog.when(
      loading: () => const LoadingState(message: 'Loading the skin catalogue…'),
      error: (Object error, StackTrace _) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(contentCatalogProvider),
      ),
      data: _buildCatalogue,
    );
  }

  Widget _buildCatalogue(ContentCatalog catalog) {
    final Set<String> owned = ref.watch(ownedSkinUuidsProvider);
    final Set<String> inShop = ref.watch(skinsInShopTodayProvider);
    final ShopSightings sightings = ref.watch(shopSightingsProvider);
    final Set<String> wishlisted = ref
        .watch(wishlistControllerProvider)
        .map((WishlistEntry e) => e.skinUuid)
        .toSet();

    final DateTime now = DateTime.now();
    SkinAvailability availabilityOf(WeaponSkin skin) => SkinAvailability.of(
      skinUuid: skin.uuid,
      inShopToday: inShop,
      sightings: sightings,
      now: now,
    );

    final List<WeaponSkin> results = _query.apply(
      catalog.browsableSkins,
      tierOf: catalog.tierOf,
      isOwned: (WeaponSkin s) => owned.contains(s.uuid),
      isWishlisted: (WeaponSkin s) => wishlisted.contains(s.uuid),
      availabilityOf: availabilityOf,
    );

    return CustomScrollView(
      // Keeps the search field reachable while scrolled into a long list, and
      // keeps the keyboard from covering what it filters.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                title: 'Catalogue',
                subtitle: _query.isFiltered
                    ? '${results.length} of '
                          '${catalog.browsableSkins.length} skins'
                    : '${catalog.browsableSkins.length} skins',
                trailing: _query.isFiltered
                    ? TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Clear'),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (String value) =>
                    setState(() => _query = _query.copyWith(search: value)),
                decoration: InputDecoration(
                  hintText: 'Search skins or weapons…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(
                              () => _query = _query.copyWith(search: ''),
                            );
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openFilters(catalog),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(
                        _query.activeFilterCount == 0
                            ? 'Filter'
                            : 'Filter · ${_query.activeFilterCount}',
                      ),
                      style: _query.activeFilterCount == 0
                          ? null
                          : OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.accent),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openSort,
                      icon: const Icon(Icons.swap_vert_rounded, size: 18),
                      label: Text(
                        _query.sort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (results.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'Try a different name, or loosen the filters.',
            ),
          )
        else
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
                    childAspectRatio: 1.12,
                  ),
              itemCount: results.length,
              itemBuilder: (BuildContext context, int index) {
                final WeaponSkin skin = results[index];
                return _CatalogueTile(
                  skin: skin,
                  tier: catalog.tierOf(skin),
                  isOwned: owned.contains(skin.uuid),
                  availability: availabilityOf(skin),
                );
              },
            ),
          ),
      ],
    );
  }

  void _clearFilters() {
    _search.clear();
    setState(() => _query = CatalogueQuery(sort: _query.sort));
  }

  Future<void> _openFilters(ContentCatalog catalog) async {
    final List<String> categories =
        catalog.browsableSkins
            .map((WeaponSkin s) => s.weaponCategory)
            .toSet()
            .toList()
          ..sort(
            (String a, String b) => SkinOrdering.categoryIndex(
              a,
            ).compareTo(SkinOrdering.categoryIndex(b)),
          );

    final CatalogueQuery? updated = await CatalogueFilterSheet.open(
      context,
      query: _query,
      tiers: rarityColoursOf(catalog.tiers.values),
      categories: categories,
    );
    if (updated != null && mounted) setState(() => _query = updated);
  }

  Future<void> _openSort() async {
    final CatalogueSort? picked = await CatalogueSortSheet.open(
      context,
      current: _query.sort,
    );
    if (picked != null && mounted) {
      setState(() => _query = _query.copyWith(sort: picked));
    }
  }
}

/// One skin in the grid. Tapping it opens the same detail page the shop does.
class _CatalogueTile extends ConsumerWidget {
  const _CatalogueTile({
    required this.skin,
    required this.tier,
    required this.isOwned,
    required this.availability,
  });

  final WeaponSkin skin;
  final ContentTier? tier;
  final bool isOwned;
  final SkinAvailability availability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tier?.color ?? AppColors.borderStrong;
    final bool isWishlisted = ref.watch(isWishlistedProvider(skin.uuid));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: () => SkinDetailPage.open(
          context,
          skin: skin,
          tier: tier,
          isOwned: isOwned,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(
              color: availability is InShopToday
                  ? AppColors.accent
                  : AppColors.border,
            ),
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
              Row(
                children: <Widget>[
                  if (isOwned)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: AppColors.success,
                    ),
                  if (isWishlisted) ...<Widget>[
                    if (isOwned) const SizedBox(width: 3),
                    const Icon(
                      Icons.favorite_rounded,
                      size: 13,
                      color: AppColors.accent,
                    ),
                  ],
                  const Spacer(),
                  TierBadge(tier: tier, compact: true),
                ],
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
                style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 3),
              DroughtChip(availability: availability),
            ],
          ),
        ),
      ),
    );
  }
}
