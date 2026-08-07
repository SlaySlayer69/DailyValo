/// A player's competitive standing.
///
/// Exists as a type rather than a record so "unranked" and "unknown" stay
/// distinguishable: a null [CompetitiveStanding] means the lookup failed, while
/// [CompetitiveStanding.unranked] means Riot answered and the player has no
/// rank this act. Rendering the first as the second is a lie the user cannot
/// tell apart from a bug.
class CompetitiveStanding {
  const CompetitiveStanding({required this.tier, required this.rankedRating});

  /// Riot's numeric tier: 0 = unranked, 3 = Iron 1, 27 = Radiant.
  final int tier;

  /// Ranked Rating within the tier, 0–100.
  final int rankedRating;

  const CompetitiveStanding.unranked() : tier = 0, rankedRating = 0;

  bool get isUnranked => tier == 0;
}
