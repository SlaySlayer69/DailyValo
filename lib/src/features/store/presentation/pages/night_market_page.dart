import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/countdown.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';
import '../../data/models/shop.dart';
import '../widgets/share_button.dart';
import '../widgets/share_card.dart';
import '../widgets/skin_card.dart';

/// Tab 2 — the Night Market, which only exists for a couple of weeks per act.
///
/// The empty state is therefore the *normal* state most of the year, and is
/// written to say so rather than reading like a failure.
class NightMarketPage extends ConsumerWidget {
  const NightMarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Shop> shop = ref.watch(shopControllerProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => ref.read(shopControllerProvider.notifier).refresh(),
      child: shop.when(
        loading: () => const _Scrollable(
          child: LoadingState(message: 'Checking the Night Market…'),
        ),
        error: (Object error, StackTrace _) => _Scrollable(
          child: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(shopControllerProvider),
          ),
        ),
        data: (Shop data) => data.hasNightMarket
            ? _MarketContent(shop: data)
            : const _Scrollable(
                child: EmptyState(
                  icon: Icons.nightlight_round,
                  title: 'No Night Market running',
                  message:
                      'Riot opens the Night Market for about two weeks each '
                      'act. DailyValo checks on every shop refresh and will '
                      'show your discounted offers here the moment it does.',
                ),
              ),
      ),
    );
  }
}

class _MarketContent extends ConsumerWidget {
  const _MarketContent({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int totalSavings = shop.nightMarket.fold<int>(
      0,
      (int sum, NightMarketDeal d) => sum + d.savings,
    );
    final DateTime? endsAt = shop.nightMarketEndsAt;

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
          title: 'Night Market',
          subtitle: '${shop.nightMarket.length} discounted offers',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ShareButton(
                title: 'Night Market',
                entries: shop.nightMarket
                    .map(ShareEntry.fromDeal)
                    .toList(growable: false),
                shareText: 'My Valorant Night Market.',
              ),
              if (endsAt != null)
                CountdownPill(
                  target: endsAt,
                  label: 'Ends in',
                  icon: Icons.nightlight_round,
                  onElapsed: () =>
                      ref.read(shopControllerProvider.notifier).refresh(),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SavingsSummary(total: totalSavings),
        const SizedBox(height: AppSpacing.lg),
        for (final NightMarketDeal deal in shop.nightMarket) ...<Widget>[
          SkinCard(
            skin: deal.skin,
            tier: deal.tier,
            isWishlisted: deal.isWishlisted,
            // Riot marks a card as unseen until the player flips it in game;
            // dimming it here mirrors that without pretending we can reveal it.
            dimmed: !deal.isSeen,
            badge: _DiscountBadge(percent: deal.discountPercent),
            priceOverride: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CurrencyAmount(
                  amount: deal.price,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.discount,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${deal.basePrice}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            onToggleWishlist: () => ref
                .read(wishlistControllerProvider.notifier)
                .toggle(deal.skin),
            onTap: () => SkinDetailPage.open(
              context,
              skin: deal.skin,
              tier: deal.tier,
              price: deal.price,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _SavingsSummary extends StatelessWidget {
  const _SavingsSummary({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.discount.withValues(alpha: 0.10),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.discount.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.savings_outlined,
            color: AppColors.discount,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Buying everything here saves you',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          CurrencyAmount(
            amount: total,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppColors.discount),
          ),
        ],
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.discount,
        borderRadius: const BorderRadius.all(Radius.circular(5)),
      ),
      child: Text(
        '-$percent%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.background,
          fontSize: 10,
          letterSpacing: 0.4,
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
