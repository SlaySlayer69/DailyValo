/// One signed-in Riot account.
///
/// Identity is the **puuid**, not the Riot ID: a Riot ID can be changed, and
/// two accounts can hold the same one at different times. Everything scoped to
/// an account on this device — session, cookie, wishlist, shop baseline,
/// collection, profile — is keyed by it.
class Account {
  const Account({
    required this.puuid,
    required this.gameName,
    required this.tagLine,
    required this.slot,
    required this.addedAt,
  });

  final String puuid;

  /// `SlaySlayer`. What the notification is titled with — the tag says nothing
  /// useful when the point is telling two of your own accounts apart.
  final String gameName;

  final String tagLine;

  /// A small, stable number, allocated on the first sign-in and never reused
  /// while the account is present.
  ///
  /// Notification ids are derived from it. A position in the account list will
  /// not do: removing the first of three accounts would shift the others down,
  /// and the notification Android is holding for one account would suddenly
  /// belong to another — replacing it, or being cancelled by it.
  final int slot;

  /// Null only for [signedOut].
  final DateTime? addedAt;

  String get riotId => tagLine.isEmpty ? gameName : '$gameName#$tagLine';

  /// The placeholder used before anyone has signed in, and in demo mode.
  ///
  /// An empty puuid is what tells the graph there is no session to restore. It
  /// still scopes storage, so demo-mode caches do not contaminate a real
  /// account's — and are not inherited by the first account to sign in.
  static const Account signedOut = Account(
    puuid: '',
    gameName: '',
    tagLine: '',
    slot: 0,
    addedAt: null,
  );

  /// The title of this account's notifications.
  String get notificationTitle => gameName.isEmpty ? riotId : gameName;

  Account copyWith({String? gameName, String? tagLine}) => Account(
    puuid: puuid,
    gameName: gameName ?? this.gameName,
    tagLine: tagLine ?? this.tagLine,
    slot: slot,
    addedAt: addedAt,
  );

  static Account? fromJson(Map<String, dynamic> json) {
    final Object? puuid = json['puuid'];
    if (puuid is! String || puuid.isEmpty) return null;
    return Account(
      puuid: puuid,
      gameName: json['gameName'] as String? ?? '',
      tagLine: json['tagLine'] as String? ?? '',
      slot: json['slot'] as int? ?? 0,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'puuid': puuid,
    'gameName': gameName,
    'tagLine': tagLine,
    'slot': slot,
    'addedAt': (addedAt ?? DateTime.now()).toIso8601String(),
  };

  @override
  bool operator ==(Object other) => other is Account && other.puuid == puuid;

  @override
  int get hashCode => puuid.hashCode;

  @override
  String toString() => 'Account($riotId, slot $slot)';
}
