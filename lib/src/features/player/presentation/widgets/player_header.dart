import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/remote_image.dart';
import '../../../content/data/models/content_catalog.dart';
import '../../../content/data/models/content_tier.dart';
import '../../data/models/player_profile.dart';
import 'currency_chip.dart';

/// The persistent header: Riot ID, competitive rank, and the VP / RP / KC
/// balances.
///
/// Sits above the tab content rather than inside each page so it does not
/// scroll away — it is the app's status line, and the wallet balance is the
/// number people open this app to check.
class PlayerHeader extends ConsumerWidget {
  const PlayerHeader({super.key, this.onTapProfile});

  final VoidCallback? onTapProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlayerProfile> profile = ref.watch(
      playerControllerProvider,
    );
    final AsyncValue<ContentCatalog> catalog = ref.watch(
      contentCatalogProvider,
    );
    final bool isDemo = ref.watch(appModeProvider) == AppMode.demo;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: profile.when(
        loading: () => const _HeaderSkeleton(),
        // Reaching this now means there is no session at all — every network
        // failure is contained inside the repository and still yields a
        // profile built from the session.
        error: (Object _, StackTrace _) => _HeaderFallback(
          message: 'Not signed in',
          onTap: onTapProfile,
        ),
        data: (PlayerProfile data) => _HeaderContent(
          profile: data,
          tier: catalog.valueOrNull?.competitiveTier(data.competitiveTier),
          isDemo: isDemo,
          onTapProfile: onTapProfile,
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.profile,
    required this.tier,
    required this.isDemo,
    this.onTapProfile,
  });

  final PlayerProfile profile;
  final CompetitiveTier? tier;
  final bool isDemo;
  final VoidCallback? onTapProfile;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // Identity on top, wallet as a full-width strip underneath. Three balances
    // stacked down the right-hand side would have made the header taller than
    // this and left the currencies competing with the Riot ID for width.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _RankBadge(tier: tier),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          profile.riotId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge,
                        ),
                      ),
                      if (isDemo) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        const _DemoBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _rankLabel(tier, profile.rankedRating, profile.rankKnown),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: profile.rankKnown
                          ? (tier?.displayColor ?? AppColors.textTertiary)
                          : AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            if (onTapProfile != null)
              IconButton(
                onPressed: onTapProfile,
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Account',
                color: AppColors.textTertiary,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _WalletStrip(wallet: profile.wallet, known: profile.walletKnown),
      ],
    );
  }

  static String _rankLabel(CompetitiveTier? tier, int rr, bool known) {
    // "Unranked" is a claim about the account; only make it when Riot actually
    // told us so. A failed lookup says so instead.
    if (!known) return 'Rank unavailable';
    if (tier == null || tier.isUnranked) return 'Unranked';
    return '${Formatters.titleCase(tier.tierName)} · $rr RR';
  }
}

/// VP, RP and Kingdom Credits, in the order the shop spends them.
///
/// Kingdom Credits earn their place here now that the Accessory Store is on the
/// shop tab: it is the only section priced in them, and "can I afford this
/// spray?" is unanswerable without the balance.
class _WalletStrip extends StatelessWidget {
  const _WalletStrip({required this.wallet, required this.known});

  final Wallet wallet;
  final bool known;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // Equal thirds: the three balances are peers, and fixed widths keep the
        // strip from reflowing every time a purchase changes a digit count.
        Expanded(
          child: BalanceChip(
            amount: wallet.valorantPoints,
            currency: Currency.valorantPoints,
            known: known,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: BalanceChip(
            amount: wallet.radianitePoints,
            currency: Currency.radianitePoints,
            known: known,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: BalanceChip(
            amount: wallet.kingdomCredits,
            currency: Currency.kingdomCredits,
            known: known,
          ),
        ),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({this.tier});

  final CompetitiveTier? tier;

  @override
  Widget build(BuildContext context) {
    final CompetitiveTier? t = tier;
    final Color accent = t?.displayColor ?? AppColors.borderStrong;

    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(4),
      child: t == null || t.isUnranked
          ? Icon(Icons.shield_outlined, size: 20, color: accent)
          : RemoteImage(
              url: t.largeIcon ?? t.smallIcon,
              fallbackIcon: Icons.shield_outlined,
            ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        'DEMO',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.warning,
          fontSize: 9,
        ),
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 14,
                    width: 130,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Placeholder chips so the header does not change height — and shove
        // the tab content down — the moment the profile resolves.
        Row(
          children: <Widget>[
            for (int i = 0; i < 3; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  height: 29,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback({required this.message, this.onTap});

  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.person_off_outlined,
          color: AppColors.textTertiary,
          size: 22,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (onTap != null)
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.more_vert_rounded),
            color: AppColors.textTertiary,
          ),
      ],
    );
  }
}
