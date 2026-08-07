import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/content_tier.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../../../content/presentation/widgets/tier_badge.dart';
import '../../../player/presentation/widgets/currency_chip.dart';
import '../widgets/chroma_selector.dart';
import '../widgets/level_list.dart';
import '../widgets/skin_video_sheet.dart';

/// Full-screen detail view for a skin: artwork, variants, and every upgrade
/// level with what it actually adds.
class SkinDetailPage extends ConsumerStatefulWidget {
  const SkinDetailPage({
    required this.skin,
    super.key,
    this.tier,
    this.price,
    this.isOwned = false,
  });

  final WeaponSkin skin;
  final ContentTier? tier;

  /// Shown when the skin is currently on offer.
  final int? price;

  final bool isOwned;

  /// Opens the detail page. Kept next to the page so callers do not have to
  /// know how it is routed.
  static Future<void> open(
    BuildContext context, {
    required WeaponSkin skin,
    ContentTier? tier,
    int? price,
    bool isOwned = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => SkinDetailPage(
          skin: skin,
          tier: tier,
          price: price,
          isOwned: isOwned,
        ),
      ),
    );
  }

  @override
  ConsumerState<SkinDetailPage> createState() => _SkinDetailPageState();
}

class _SkinDetailPageState extends ConsumerState<SkinDetailPage> {
  int _chromaIndex = 0;

  WeaponSkin get _skin => widget.skin;

  SkinChroma? get _selectedChroma =>
      _skin.chromas.isEmpty ? null : _skin.chromas[_chromaIndex];

  /// The variant's own render when it has one, otherwise the skin's.
  String? get _artwork =>
      _selectedChroma?.fullRender ?? _selectedChroma?.displayIcon ?? _skin.artwork;

  /// Clip for the current selection.
  ///
  /// Falls back to the base level's clip when the selected chroma has none —
  /// Riot only publishes variant clips for chromas with unique VFX, and showing
  /// the base skin in motion is better than showing nothing.
  String? get _previewVideoUrl {
    final SkinChroma? chroma = _selectedChroma;
    if (chroma != null && chroma.hasVideo) return chroma.streamedVideo;
    return _skin.previewVideoUrl;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = widget.tier?.color ?? AppColors.borderStrong;
    final bool isWishlisted = ref.watch(isWishlistedProvider(_skin.uuid));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            leading: const BackButton(),
            actions: <Widget>[
              IconButton(
                onPressed: _toggleWishlist,
                tooltip: isWishlisted
                    ? 'Remove from wishlist'
                    : 'Add to wishlist',
                icon: Icon(
                  isWishlisted
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isWishlisted
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroArtwork(
                imageUrl: _artwork,
                wallpaper: _skin.wallpaper,
                accent: accent,
                // Chroma clips are reached from the artwork rather than from
                // the swatch: a 52px swatch is not a sane tap target for two
                // different actions, and tapping it already swaps the render.
                onPlayPreview: _previewVideoUrl == null
                    ? null
                    : () => SkinVideoSheet.open(
                        context,
                        videoUrl: _previewVideoUrl!,
                        title: _selectedChroma == null
                            ? 'Preview'
                            : _selectedChroma!.shortName(_skin.displayName),
                        subtitle: _skin.displayName,
                      ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    TierBadge(tier: widget.tier),
                    if (widget.tier != null) const SizedBox(width: AppSpacing.sm),
                    Text(
                      _skin.weaponCategory.toUpperCase(),
                      style: text.labelSmall,
                    ),
                    const Spacer(),
                    if (widget.isOwned) const _OwnedPill(),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _skin.weaponName.toUpperCase(),
                  style: text.labelMedium?.copyWith(color: accent),
                ),
                const SizedBox(height: 4),
                Text(_skin.displayName, style: text.displaySmall),
                if (widget.price != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: <Widget>[
                      Text('In your shop for', style: text.bodyMedium),
                      const SizedBox(width: AppSpacing.sm),
                      CurrencyAmount(
                        amount: widget.price!,
                        style: text.titleLarge,
                      ),
                    ],
                  ),
                ],

                if (_skin.hasChromas) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  ChromaSelector(
                    skin: _skin,
                    selectedIndex: _chromaIndex,
                    onSelected: (int index) =>
                        setState(() => _chromaIndex = index),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),
                LevelList(skin: _skin, accent: accent),

                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: _toggleWishlist,
                  icon: Icon(
                    isWishlisted
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 19,
                  ),
                  label: Text(
                    isWishlisted ? 'On your wishlist' : 'Add to wishlist',
                  ),
                  style: isWishlisted
                      ? FilledButton.styleFrom(
                          backgroundColor: AppColors.surfaceVariant,
                          foregroundColor: AppColors.accent,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWishlist() async {
    final bool added = await ref
        .read(wishlistControllerProvider.notifier)
        .toggle(_skin);
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            added
                ? '${_skin.displayName} added to your wishlist'
                : '${_skin.displayName} removed from your wishlist',
          ),
        ),
      );
  }
}

/// Key art behind the collapsing app bar, with the skin render on top.
class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({
    required this.imageUrl,
    required this.wallpaper,
    required this.accent,
    this.onPlayPreview,
  });

  final String? imageUrl;
  final String? wallpaper;
  final Color accent;

  /// Null when Riot publishes no clip for this skin at all.
  final VoidCallback? onPlayPreview;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 0.95,
              colors: <Color>[
                accent.withValues(alpha: 0.28),
                AppColors.background,
              ],
            ),
          ),
        ),
        if (wallpaper != null)
          Opacity(
            opacity: 0.30,
            child: RemoteImage(url: wallpaper, fit: BoxFit.cover),
          ),
        // Ensures the app bar controls stay legible over bright key art.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.0, 0.45, 1.0],
              colors: <Color>[
                Color(0xB3000000),
                Color(0x00000000),
                AppColors.background,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl + AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: RemoteImage(url: imageUrl, fit: BoxFit.contain),
        ),
        if (onPlayPreview != null)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: _PlayPreviewButton(accent: accent, onPressed: onPlayPreview!),
          ),
      ],
    );
  }
}

/// Sits on the artwork rather than in the content below it, so it reads as
/// "play what you are looking at".
class _PlayPreviewButton extends StatelessWidget {
  const _PlayPreviewButton({required this.accent, required this.onPressed});

  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.92),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.play_arrow_rounded, size: 18, color: accent),
              const SizedBox(width: 5),
              Text(
                'PREVIEW',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedPill extends StatelessWidget {
  const _OwnedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_rounded, size: 12, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            'IN YOUR COLLECTION',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.success,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}
