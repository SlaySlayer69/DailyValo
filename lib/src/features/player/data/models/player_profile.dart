/// The player's currency balances.
class Wallet {
  const Wallet({
    this.valorantPoints = 0,
    this.radianitePoints = 0,
    this.kingdomCredits = 0,
  });

  final int valorantPoints;
  final int radianitePoints;
  final int kingdomCredits;

  static const Wallet empty = Wallet();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'vp': valorantPoints,
    'rp': radianitePoints,
    'kc': kingdomCredits,
  };

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    valorantPoints: (json['vp'] as num?)?.toInt() ?? 0,
    radianitePoints: (json['rp'] as num?)?.toInt() ?? 0,
    kingdomCredits: (json['kc'] as num?)?.toInt() ?? 0,
  );
}

/// Everything the app header shows: who you are, your rank, your balances.
///
/// Cached so the header renders instantly on a cold start rather than showing
/// three shimmering placeholders while two PD calls complete.
class PlayerProfile {
  const PlayerProfile({
    required this.puuid,
    required this.gameName,
    required this.tagLine,
    required this.wallet,
    required this.competitiveTier,
    required this.rankedRating,
    required this.updatedAt,
  });

  final String puuid;
  final String gameName;
  final String tagLine;
  final Wallet wallet;

  /// Riot's numeric competitive tier (0 = unranked, 27 = Radiant).
  final int competitiveTier;

  /// RR within the current tier, 0–100.
  final int rankedRating;

  final DateTime updatedAt;

  String get riotId => tagLine.isEmpty ? gameName : '$gameName#$tagLine';

  PlayerProfile copyWith({
    Wallet? wallet,
    int? competitiveTier,
    int? rankedRating,
  }) => PlayerProfile(
    puuid: puuid,
    gameName: gameName,
    tagLine: tagLine,
    wallet: wallet ?? this.wallet,
    competitiveTier: competitiveTier ?? this.competitiveTier,
    rankedRating: rankedRating ?? this.rankedRating,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'puuid': puuid,
    'gameName': gameName,
    'tagLine': tagLine,
    'wallet': wallet.toJson(),
    'competitiveTier': competitiveTier,
    'rankedRating': rankedRating,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    final Object? wallet = json['wallet'];
    return PlayerProfile(
      puuid: json['puuid'] as String? ?? '',
      gameName: json['gameName'] as String? ?? '',
      tagLine: json['tagLine'] as String? ?? '',
      wallet: wallet is Map<String, dynamic>
          ? Wallet.fromJson(wallet)
          : Wallet.empty,
      competitiveTier: (json['competitiveTier'] as num?)?.toInt() ?? 0,
      rankedRating: (json['rankedRating'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
