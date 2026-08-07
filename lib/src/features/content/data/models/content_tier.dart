import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Skin rarity: Select / Deluxe / Premium / Ultra / Exclusive.
///
/// Colours come from the API rather than a hard-coded map so a new tier shows
/// up correctly without an app update.
class ContentTier {
  const ContentTier({
    required this.uuid,
    required this.displayName,
    required this.devName,
    required this.rank,
    required this.highlightColor,
    this.displayIcon,
  });

  final String uuid;

  /// Localised, e.g. `Ultra Edition`.
  final String displayName;

  /// Stable English key, e.g. `Ultra`. Safe to switch on.
  final String devName;

  /// Sort order, 0 (Select) .. 4 (Exclusive).
  final int rank;

  /// `RRGGBBAA` hex from the API.
  final String highlightColor;

  final String? displayIcon;

  Color get color => AppColors.fromRgbaHex(highlightColor);

  factory ContentTier.fromJson(Map<String, dynamic> json) => ContentTier(
    uuid: json['uuid'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    devName: json['devName'] as String? ?? '',
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    highlightColor: json['highlightColor'] as String? ?? '5a656eff',
    displayIcon: json['displayIcon'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uuid': uuid,
    'displayName': displayName,
    'devName': devName,
    'rank': rank,
    'highlightColor': highlightColor,
    'displayIcon': displayIcon,
  };
}

/// One competitive rank (Iron 1 … Radiant) from `/v1/competitivetiers`.
class CompetitiveTier {
  const CompetitiveTier({
    required this.tier,
    required this.tierName,
    required this.divisionName,
    required this.color,
    this.smallIcon,
    this.largeIcon,
  });

  /// Riot's numeric tier. 0 = Unranked, 3 = Iron 1, 27 = Radiant.
  final int tier;

  /// e.g. `IRON 1`.
  final String tierName;

  /// e.g. `IRON`.
  final String divisionName;

  /// `RRGGBBAA` hex.
  final String color;

  final String? smallIcon;
  final String? largeIcon;

  bool get isUnranked => tier == 0 || smallIcon == null;

  Color get displayColor =>
      AppColors.fromRgbaHex(color, fallback: AppColors.textSecondary);

  factory CompetitiveTier.fromJson(Map<String, dynamic> json) =>
      CompetitiveTier(
        tier: (json['tier'] as num?)?.toInt() ?? 0,
        tierName: json['tierName'] as String? ?? 'UNRANKED',
        divisionName: json['divisionName'] as String? ?? 'UNRANKED',
        color: json['color'] as String? ?? 'ffffffff',
        smallIcon: json['smallIcon'] as String?,
        largeIcon: json['largeIcon'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tier': tier,
    'tierName': tierName,
    'divisionName': divisionName,
    'color': color,
    'smallIcon': smallIcon,
    'largeIcon': largeIcon,
  };

  static const CompetitiveTier unranked = CompetitiveTier(
    tier: 0,
    tierName: 'UNRANKED',
    divisionName: 'UNRANKED',
    color: '5a656eff',
  );
}
