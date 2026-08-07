import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../skin_detail/presentation/pages/skin_detail_page.dart';
import '../../../store/data/models/shop.dart';
import '../../data/models/wishlist_entry.dart';
import '../widgets/skin_picker_sheet.dart';

/// Tab 3 — the skins the user is waiting for.
///
/// This list is what the background worker intersects the daily shop against,
/// so the page also surfaces *which* entries are in the shop right now.
class WishlistPage extends ConsumerWidget {
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WishlistEntry> entries = ref.watch(wishlistControllerProvider);

    // Offer ids currently in the shop, so a hit can be flagged inline.
    final Set<String> offersInShop =
        ref
            .watch(shopControllerProvider)
            .valueOrNull
            ?.dailyOffers
            .map((ShopOffer o) => o.offerId)
            .toSet() ??
        const <String>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => SkinPickerSheet.open(context),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add skins'),
      ),
      body: entries.isEmpty
          ? EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Your wishlist is empty',
              message:
                  'Add the skins you are hunting for. DailyValo checks your '
                  'shop after every reset and sends you an alert the moment '
                  'one shows up.',
              action: FilledButton.icon(
                onPressed: () => SkinPickerSheet.open(context),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Browse skins'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 50),
                ),
              ),
            )
          : _WishlistContent(
              entries: entries,
              offersInShop: offersInShop,
            ),
    );
  }
}

class _WishlistContent extends ConsumerWidget {
  const _WishlistContent({required this.entries, required this.offersInShop});

  final List<WishlistEntry> entries;
  final Set<String> offersInShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int hits = entries
        .where((WishlistEntry e) => offersInShop.contains(e.offerUuid))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        96, // clears the FAB
      ),
      children: <Widget>[
        SectionHeader(
          title: 'Wishlist',
          subtitle: '${entries.length} '
              '${entries.length == 1 ? 'skin' : 'skins'} tracked',
          trailing: hits == 0
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentSubtle,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.sm),
                    ),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    '$hits IN SHOP',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final WishlistEntry entry in entries) ...<Widget>[
          _WishlistTile(
            entry: entry,
            isInShop: offersInShop.contains(entry.offerUuid),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _WishlistTile extends ConsumerWidget {
  const _WishlistTile({required this.entry, required this.isInShop});

  final WishlistEntry entry;
  final bool isInShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>(entry.skinUuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.18),
          borderRadius: AppRadius.card,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      onDismissed: (DismissDirection _) {
        ref.read(wishlistControllerProvider.notifier).remove(entry.skinUuid);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('${entry.skinName} removed')),
          );
      },
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => _openDetail(context, ref),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              border: Border.all(
                color: isInShop ? AppColors.accent : AppColors.border,
                width: isInShop ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 40,
                  width: 88,
                  child: RemoteImage(url: entry.imageUrl),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        entry.weaponName.toUpperCase(),
                        style: text.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.skinName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                      if (isInShop) ...<Widget>[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 13,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'In your shop today',
                              style: text.bodySmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => ref
                      .read(wishlistControllerProvider.notifier)
                      .remove(entry.skinUuid),
                  icon: const Icon(Icons.favorite_rounded, size: 20),
                  color: AppColors.accent,
                  tooltip: 'Remove from wishlist',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the full detail page, which needs the catalogue entry rather than
  /// the denormalised wishlist row.
  void _openDetail(BuildContext context, WidgetRef ref) {
    final ContentCatalog? catalog = ref
        .read(contentCatalogProvider)
        .valueOrNull;
    final WeaponSkin? skin = catalog?.skinByUuid(entry.skinUuid);
    if (catalog == null || skin == null) return;

    SkinDetailPage.open(
      context,
      skin: skin,
      tier: catalog.tierOf(skin),
    );
  }
}
