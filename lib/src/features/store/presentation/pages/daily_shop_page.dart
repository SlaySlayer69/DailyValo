import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/countdown.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';
import '../../data/models/shop.dart';
import '../widgets/accessory_card.dart';
import '../widgets/bundle_card.dart';
import '../widgets/skin_card.dart';

/// Tab 1 — the four daily offers and the countdown to the next rotation.
class DailyShopPage extends ConsumerWidget {
  const DailyShopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Shop> shop = ref.watch(shopControllerProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => ref.read(shopControllerProvider.notifier).refresh(),
      child: shop.when(
        // `skipLoadingOnRefresh` is the default for `when`, so a pull-to-refresh
        // keeps the current offers on screen instead of flashing a spinner.
        loading: () => const _ScrollableCenter(
          child: LoadingState(message: 'Loading your shop…'),
        ),
        error: (Object error, StackTrace _) => _ScrollableCenter(
          child: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(shopControllerProvider),
          ),
        ),
        data: (Shop data) => _ShopContent(shop: data),
      ),
    );
  }
}

class _ShopContent extends ConsumerWidget {
  const _ShopContent({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shop.dailyOffers.isEmpty) {
      return const _ScrollableCenter(
        child: EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No offers right now',
          message:
              'Riot returned an empty storefront. Pull down to try again in a '
              'moment.',
        ),
      );
    }

    final List<ShopOffer> hits = shop.wishlistHits;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SectionHeader(
          title: 'Daily Shop',
          subtitle: 'Today\'s offers',
          trailing: CountdownPill(
            target: shop.dailyResetAt,
            label: 'Resets in',
            // The moment the countdown hits zero the cached storefront is
            // stale by definition — refetch rather than showing 00:00:00.
            onElapsed: () =>
                ref.read(shopControllerProvider.notifier).refresh(),
          ),
        ),
        if (hits.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _WishlistBanner(hits: hits),
        ],
        const SizedBox(height: AppSpacing.lg),
        for (final ShopOffer offer in shop.dailyOffers) ...<Widget>[
          SkinCard(
            skin: offer.skin,
            tier: offer.tier,
            price: offer.price,
            isOwned: offer.isOwned,
            isWishlisted: offer.isWishlisted,
            onToggleWishlist: () => ref
                .read(wishlistControllerProvider.notifier)
                .toggle(offer.skin),
            onTap: () => SkinDetailPage.open(
              context,
              skin: offer.skin,
              tier: offer.tier,
              price: offer.price,
              isOwned: offer.isOwned,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        if (shop.hasAccessories) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Accessories',
            subtitle: '${shop.accessories.length} offers',
            // Its own countdown: the accessory store rotates weekly, so it is
            // usually days out while the daily shop is hours out.
            trailing: shop.accessoryResetAt == null
                ? null
                : CountdownPill(
                    target: shop.accessoryResetAt!,
                    label: 'Resets in',
                    icon: Icons.category_outlined,
                    onElapsed: () =>
                        ref.read(shopControllerProvider.notifier).refresh(),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final AccessoryOffer offer in shop.accessories) ...<Widget>[
            AccessoryCard(offer: offer),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],

        if (shop.hasBundles) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Featured Bundles',
            subtitle: shop.bundles.length == 1
                ? shop.bundles.first.displayName
                : '${shop.bundles.length} bundles',
          ),
          const SizedBox(height: AppSpacing.md),
          for (final BundleOffer bundle in shop.bundles) ...<Widget>[
            BundleCard(
              bundle: bundle,
              onExpired: () =>
                  ref.read(shopControllerProvider.notifier).refresh(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],

        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'Skins and bundles in Valorant Points · Accessories in Kingdom '
            'Credits · Shop resets 00:00 UTC',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// The in-app counterpart to the wishlist notification.
class _WishlistBanner extends StatelessWidget {
  const _WishlistBanner({required this.hits});

  final List<ShopOffer> hits;

  @override
  Widget build(BuildContext context) {
    final String names = hits
        .map((ShopOffer o) => o.skin.displayName)
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSubtle,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.favorite_rounded,
            color: AppColors.accent,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hits.length == 1
                      ? 'An item on your wishlist is in your shop!'
                      : '${hits.length} wishlist items are in your shop!',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  names,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps `RefreshIndicator` usable on states that are shorter than the viewport.
class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

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
