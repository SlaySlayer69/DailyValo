/// What one rank source did when it was asked.
///
/// Riot exposes competitive rank through several endpoints whose availability
/// varies by account and region, so the lookup tries them in turn. Recording
/// each attempt is what lets the Diagnostics screen say *which* source answered
/// and which failed — otherwise a wrong rank is indistinguishable from a
/// missing one, and debugging it on someone else's phone is guesswork.
class RankAttempt {
  const RankAttempt(this.source, {required this.ok, this.note});

  /// e.g. `MMR record (current act)`.
  final String source;

  /// Whether the endpoint answered at all — not whether it held a rank.
  final bool ok;

  /// Status code on failure, or a short shape summary on success.
  final String? note;

  @override
  String toString() => '$source: ${ok ? 'ok' : 'failed'}'
      '${note == null ? '' : ' ($note)'}';
}
