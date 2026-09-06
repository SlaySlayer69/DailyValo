/// When each skin was last seen in this account's daily shop.
///
/// The shop tells you what is on offer today. The question people actually ask
/// is the other one — *how long have I been waiting for this?* — and nothing in
/// Riot's API answers it: there is no history endpoint, and the storefront is
/// only ever a snapshot of now. So it is recorded here, one date per skin, as
/// each shop goes past.
///
/// [trackedSince] is the important half. Without it "never seen" is a lie on a
/// device that has only been watching for three days: it would read the same as
/// a skin genuinely absent for a year, and the first is worth nothing while the
/// second is the whole point.
class ShopSightings {
  const ShopSightings({required this.trackedSince, required this.lastSeen});

  /// Nothing recorded yet, watching from [now] on.
  factory ShopSightings.startingAt(DateTime now) =>
      ShopSightings(trackedSince: _day(now), lastSeen: const <String, DateTime>{});

  /// When this device started watching this account's shop.
  final DateTime trackedSince;

  /// Skin UUID -> the day it was last offered. Dates only; the shop rotates
  /// once a day, so the time of day says nothing.
  final Map<String, DateTime> lastSeen;

  int daysTracked(DateTime now) =>
      _day(now).difference(_day(trackedSince)).inDays;

  /// Days since [skinUuid] was last offered, or null if it never has been
  /// while this device was watching.
  ///
  /// Both ends are truncated to midnight before subtracting. `Duration.inDays`
  /// floors, so comparing a stored 14:30 against a 02:00 "now" would report a
  /// drought one day shorter than it is — and would do it only for records that
  /// arrived from somewhere other than [record], which is exactly the kind of
  /// bug that survives every test written against the happy path.
  int? daysSince(String skinUuid, DateTime now) {
    final DateTime? seen = lastSeen[skinUuid];
    if (seen == null) return null;
    return _day(now).difference(_day(seen)).inDays;
  }

  /// Records a shop. Returns a new instance; nothing mutates in place.
  ///
  /// Re-recording the same day is a no-op by construction — the same date
  /// simply overwrites itself — which matters because the shop is resolved on
  /// every tab open, not once per rotation.
  ShopSightings record(Iterable<String> skinUuids, DateTime now) {
    final DateTime today = _day(now);
    return ShopSightings(
      trackedSince: today.isBefore(trackedSince) ? today : trackedSince,
      lastSeen: <String, DateTime>{
        ...lastSeen,
        for (final String uuid in skinUuids) uuid: today,
      },
    );
  }

  /// Midnight local. Two shops on the same calendar day are one sighting.
  static DateTime _day(DateTime at) =>
      DateTime(at.year, at.month, at.day);

  static ShopSightings? fromJson(Map<String, dynamic> json) {
    final DateTime? since = DateTime.tryParse(
      json['trackedSince'] as String? ?? '',
    );
    if (since == null) return null;

    final Object? raw = json['lastSeen'];
    final Map<String, DateTime> seen = <String, DateTime>{};
    if (raw is Map) {
      raw.forEach((Object? key, Object? value) {
        if (key is! String || value is! String) return;
        final DateTime? day = DateTime.tryParse(value);
        if (day != null) seen[key] = day;
      });
    }
    return ShopSightings(trackedSince: since, lastSeen: seen);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'trackedSince': trackedSince.toIso8601String(),
    'lastSeen': <String, String>{
      for (final MapEntry<String, DateTime> e in lastSeen.entries)
        e.key: e.value.toIso8601String(),
    },
  };
}

/// What the app can say about one skin right now.
///
/// Deliberately a closed set rather than a nullable day count: "in your shop
/// today", "not seen for 47 days" and "never seen, but only watching for 3"
/// are different sentences, and a caller handed an `int?` would have to
/// reconstruct which one applies — and would get the third one wrong.
sealed class SkinAvailability {
  const SkinAvailability();

  /// Resolves a skin against today's shop and the recorded sightings.
  factory SkinAvailability.of({
    required String skinUuid,
    required Set<String> inShopToday,
    required ShopSightings sightings,
    required DateTime now,
  }) {
    if (inShopToday.contains(skinUuid)) return const InShopToday();

    final int? days = sightings.daysSince(skinUuid, now);
    if (days != null) return SeenBefore(days);

    return NeverSeen(sightings.daysTracked(now));
  }

  /// How long this skin has been away, for sorting a list by drought.
  ///
  /// A never-seen skin sorts above every dated one — it has been absent for at
  /// least as long as tracking has run, and usually far longer — and today's
  /// offers sort below zero so they never lead a "longest wait" list.
  int get droughtRank => switch (this) {
    InShopToday() => -1,
    SeenBefore(:final int days) => days,
    NeverSeen() => _neverRank,
  };

  static const int _neverRank = 1 << 30;

  /// One line for the UI, e.g. `Last seen 47 days ago`.
  String get label => switch (this) {
    InShopToday() => 'In your shop today',
    SeenBefore(days: 0) => 'In your shop earlier today',
    SeenBefore(days: 1) => 'Last seen yesterday',
    SeenBefore(:final int days) => 'Last seen $days days ago',
    // The tracking window is the whole point: "never seen" after four days
    // says nothing, and the sentence has to admit that.
    NeverSeen(daysTracked: 0) => 'Not seen yet — tracking started today',
    NeverSeen(daysTracked: 1) => 'Not seen in the 1 day tracked so far',
    NeverSeen(:final int daysTracked) =>
      'Not seen in the $daysTracked days tracked so far',
  };

  /// The same thing in the width of a chip, for grid tiles and list rows.
  String get shortLabel => switch (this) {
    InShopToday() => 'In shop',
    SeenBefore(days: 0) => 'Today',
    SeenBefore(days: 1) => '1d ago',
    SeenBefore(:final int days) => '${days}d ago',
    NeverSeen() => 'Never seen',
  };
}

/// On offer right now.
class InShopToday extends SkinAvailability {
  const InShopToday();
}

/// Offered [days] ago. Zero means earlier today — the shop rotated since.
class SeenBefore extends SkinAvailability {
  const SeenBefore(this.days);

  final int days;
}

/// Not once while this device has been watching, which has been
/// [daysTracked] days.
///
/// The count is carried because it is what makes the statement honest: "never
/// seen" after two days of tracking says nothing at all.
class NeverSeen extends SkinAvailability {
  const NeverSeen(this.daysTracked);

  final int daysTracked;
}
