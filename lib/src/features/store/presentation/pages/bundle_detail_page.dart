import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/countdown.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';
import '../../data/models/shop.dart';

/// Everything inside one Featured Bundle.
///
/// The two questions a bundle actually raises are "what is in it?" and "do I
/// have to buy all of it?", and neither is answerable from the shop card. Both
/// are answered at the top of this page, before the item list.
class BundleDetailPage extends StatelessWidget {
  const BundleDetailPage({required this.bundle, super.key});

  final BundleOffer bundle;

  static Future<void> open(BuildContext context, {required BundleOffer bundle}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => BundleDetailPage(bundle: bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RemoteImage(
                    url: bundle.info?.artwork,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.inventory_2_outlined,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: <double>[0.4, 1.0],
                        colors: <Color>[
                          Color(0x00000000),
                          Color(0xF2101216),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                Text(
                  'FEATURED BUNDLE',
                  style: text.labelSmall?.copyWith(color: AppColors.accent),
                ),
                const SizedBox(height: 4),
                Text(bundle.displayName, style: text.headlineMedium),
                if (bundle.info?.description != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(bundle.info!.description!, style: text.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.lg),
                _PricePanel(bundle: bundle),
                const SizedBox(height: AppSpacing.md),
                _PurchaseNote(wholesaleOnly: bundle.wholesaleOnly),
                const SizedBox(height: AppSpacing.xl),

                if (!bundle.hasItems)
                  const _ContentsUnavailable()
                else ...<Widget>[
                  SectionHeader(
                    title: 'Contents',
                    subtitle: '${bundle.items.length} items',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final BundleItem item in bundle.items) ...<Widget>[
                    _BundleItemRow(item: item),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PricePanel extends StatelessWidget {
  const _PricePanel({required this.bundle});

  final BundleOffer bundle;

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
              CurrencyAmount(amount: bundle.price, style: text.headlineSmall),
              if (bundle.isDiscounted) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  Formatters.points(bundle.basePrice),
                  style: text.bodyMedium?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textTertiary,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const Spacer(),
              CountdownPill(
                target: bundle.endsAt,
                label: 'Leaves in',
                icon: Icons.hourglass_bottom_rounded,
              ),
            ],
          ),
          if (bundle.isDiscounted) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Saves ${Formatters.points(bundle.savings)} VP '
              '(${bundle.discountPercent}% off)',
              style: text.bodySmall?.copyWith(color: AppColors.discount),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether the bundle can be broken up.
///
/// Called out on its own rather than buried in the item list, because it
/// changes what every price below it means: on a wholesale-only bundle the
/// per-item prices are what the items are *worth*, not what you can pay.
class _PurchaseNote extends StatelessWidget {
  const _PurchaseNote({required this.wholesaleOnly});

  final bool wholesaleOnly;

  @override
  Widget build(BuildContext context) {
    final Color color = wholesaleOnly ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.card,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            wholesaleOnly
                ? Icons.lock_outline_rounded
                : Icons.shopping_bag_outlined,
            size: 19,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  wholesaleOnly
                      ? 'Complete bundle only'
                      : 'Items can be bought separately',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  wholesaleOnly
                      ? 'Riot is not selling these items individually — the '
                            'prices below are what each part is worth.'
                      : 'You can buy any single item at the price shown, or '
                            'take the whole bundle for less.',
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

/// One item in the bundle. Skins open their detail page; accessories do not,
/// because there is nothing behind them to show.
class _BundleItemRow extends StatelessWidget {
  const _BundleItemRow({required this.item});

  final BundleItem item;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: item.isPreviewable
            ? () => SkinDetailPage.open(
                context,
                skin: item.skin!,
                tier: item.tier,
                // The bundle price, not the shop price — this is what the skin
                // costs here.
                price: item.isFree ? null : item.price,
              )
            : null,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                height: 44,
                width: 84,
                child: RemoteImage(
                  url: item.artwork,
                  fit: BoxFit.contain,
                  fallbackIcon: Icons.category_outlined,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            item.subtitle.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall,
                          ),
                        ),
                        if (item.tier != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          TierBadge(tier: item.tier, compact: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    _ItemPrice(item: item),
                  ],
                ),
              ),
              if (item.isPreviewable)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemPrice extends StatelessWidget {
  const _ItemPrice({required this.item});

  final BundleItem item;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    if (item.isFree) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'FREE IN BUNDLE',
            style: text.labelSmall?.copyWith(color: AppColors.success),
          ),
          if (item.basePrice > 0) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Text(
              Formatters.points(item.basePrice),
              style: text.bodySmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CurrencyAmount(
          amount: item.price,
          iconSize: 12,
          style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
        ),
        if (item.isDiscounted) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          Text(
            Formatters.points(item.basePrice),
            style: text.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Riot occasionally returns a bundle with no item list at all.
class _ContentsUnavailable extends StatelessWidget {
  const _ContentsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.help_outline_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Riot did not list this bundle\'s contents. Pull down on the '
              'shop tab to refetch.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
