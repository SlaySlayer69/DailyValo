import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/riot_constants.dart';
import '../../../../core/constants/valorant_api_constants.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/remote_image.dart';

/// Which in-game currency a price or balance is denominated in.
enum Currency {
  valorantPoints(RiotConstants.currencyValorantPoints, 'VP'),
  radianitePoints(RiotConstants.currencyRadianitePoints, 'RP'),
  kingdomCredits(RiotConstants.currencyKingdomCredits, 'KC');

  const Currency(this.uuid, this.shortName);

  final String uuid;
  final String shortName;

  /// Riot's own icon, served by the content CDN.
  String get iconUrl => ValorantApiConstants.currencyIcon(uuid);
}

/// `[icon] 1,775` — the standard way a price or balance is rendered.
class CurrencyAmount extends StatelessWidget {
  const CurrencyAmount({
    required this.amount,
    super.key,
    this.currency = Currency.valorantPoints,
    this.iconSize = 14,
    this.style,
    this.strikethrough = false,
  });

  final int amount;
  final Currency currency;
  final double iconSize;
  final TextStyle? style;

  /// Used for the pre-discount price in the Night Market.
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final TextStyle base =
        style ??
        Theme.of(context).textTheme.titleMedium!.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: iconSize,
          width: iconSize,
          child: RemoteImage(
            url: currency.iconUrl,
            fallbackIcon: Icons.paid_outlined,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          Formatters.points(amount),
          style: strikethrough
              ? base.copyWith(
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.textTertiary,
                  color: AppColors.textTertiary,
                )
              : base,
        ),
      ],
    );
  }
}

/// A balance as shown in the header: amount plus a wide-tracked currency label.
///
/// Text-only, deliberately. Riot serves no icon for Radianite Points (that
/// currency's `displayicon.png` 404s), so an icon here meant VP got real art
/// while RP got a generic placeholder glyph — visually inconsistent and
/// meaningless. `VP`, `RP` and `KC` are the labels players already use in game,
/// and three short words read faster in a cramped header than three small
/// images. Prices on cards keep their currency icon, where there is room and
/// only one currency is ever shown.
class BalanceChip extends StatelessWidget {
  const BalanceChip({
    required this.amount,
    required this.currency,
    super.key,
    this.known = true,
  });

  final int amount;
  final Currency currency;

  /// False when the wallet lookup failed. Renders an em dash: 0 is a perfectly
  /// plausible balance, so showing one we never received reads as fact.
  final bool known;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Centred so the three chips read as a balanced strip when the header
        // stretches them to equal widths.
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            known ? Formatters.points(amount) : '—',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: known ? AppColors.textPrimary : AppColors.textTertiary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            currency.shortName,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
