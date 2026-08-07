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

/// Searchable picker over the full skin catalogue.
///
/// ~1600 skins, so the list is virtualised and the filter runs on a lowercased
/// haystack built once per keystroke rather than per row.
class SkinPickerSheet extends ConsumerStatefulWidget {
  const SkinPickerSheet({super.key});

  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.backgroundElevated,
      builder: (BuildContext _) => const SkinPickerSheet(),
    );
  }

  @override
  ConsumerState<SkinPickerSheet> createState() => _SkinPickerSheetState();
}

class _SkinPickerSheetState extends ConsumerState<SkinPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ContentCatalog> catalog = ref.watch(
      contentCatalogProvider,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Add to wishlist',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onChanged: (String value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search skins or weapons…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: catalog.when(
                loading: () =>
                    const LoadingState(message: 'Loading skin catalogue…'),
                error: (Object error, StackTrace _) => ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(contentCatalogProvider),
                ),
                data: (ContentCatalog data) => _SkinList(
                  catalog: data,
                  query: _query,
                  scrollController: scrollController,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SkinList extends ConsumerWidget {
  const _SkinList({
    required this.catalog,
    required this.query,
    required this.scrollController,
  });

  final ContentCatalog catalog;
  final String query;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WeaponSkin> results = _filter();

    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Try a different skin line or weapon name.',
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: results.length,
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final WeaponSkin skin = results[index];
        return _SkinRow(skin: skin, tier: catalog.tierOf(skin));
      },
    );
  }

  List<WeaponSkin> _filter() {
    final List<WeaponSkin> pool = catalog.purchasableSkins;
    if (query.isEmpty) return pool;
    return pool
        .where(
          (WeaponSkin s) =>
              s.displayName.toLowerCase().contains(query) ||
              s.weaponName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class _SkinRow extends ConsumerWidget {
  const _SkinRow({required this.skin, required this.tier});

  final WeaponSkin skin;
  final ContentTier? tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isWishlisted = ref.watch(isWishlistedProvider(skin.uuid));

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: () =>
            ref.read(wishlistControllerProvider.notifier).toggle(skin),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                height: 34,
                width: 76,
                child: RemoteImage(url: skin.displayIcon ?? skin.artwork),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      skin.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      skin.weaponName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TierBadge(tier: tier, compact: true),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                isWishlisted
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 20,
                color: isWishlisted
                    ? AppColors.accent
                    : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
