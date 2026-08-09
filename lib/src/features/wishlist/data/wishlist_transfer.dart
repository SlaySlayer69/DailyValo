import 'dart:convert';

import '../../../core/errors/app_exception.dart';
import 'models/wishlist_entry.dart';

/// The shape of an exported wishlist file.
///
/// A wishlist is the one thing in this app the user built by hand — everything
/// else comes back from Riot on the next sign-in. Losing it to a reinstall (or
/// to the signing-key change) is the difference between an annoyance and
/// starting over, so it has to be movable.
///
/// The format is deliberately the app's own storage shape wrapped in a version
/// envelope, not a bespoke schema: entries already carry everything needed to
/// render a row without the catalogue, which means an import works offline and
/// on a device that has never fetched anything.
class WishlistTransfer {
  const WishlistTransfer({required this.entries, required this.exportedAt});

  /// Bumped only if the entry shape changes incompatibly. An importer that
  /// meets a newer version says so instead of silently dropping fields.
  static const int formatVersion = 1;

  static const String fileKind = 'dailyvalo.wishlist';

  final List<WishlistEntry> entries;
  final DateTime exportedAt;

  String encode() => const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'kind': fileKind,
    'version': formatVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'count': entries.length,
    'entries': entries.map((WishlistEntry e) => e.toJson()).toList(),
  });

  /// Suggested filename — dated, because people export more than once.
  String get fileName {
    final String d = exportedAt.toIso8601String().split('T').first;
    return 'dailyvalo-wishlist-$d.json';
  }

  /// Parses an exported file.
  ///
  /// Throws [ParseException] with something a person can act on. This is the
  /// one place in the app that reads a file the user chose, so "it didn't work"
  /// is not an acceptable answer — they need to know whether they picked the
  /// wrong file or the right file is broken.
  factory WishlistTransfer.decode(String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const ParseException(
        'That file is not valid JSON. Pick the .json file DailyValo exported.',
      );
    }

    if (raw is! Map<String, dynamic>) {
      throw const ParseException('That file does not contain a wishlist.');
    }

    if (raw['kind'] != fileKind) {
      throw const ParseException(
        'That is not a DailyValo wishlist export.',
      );
    }

    final int version = (raw['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw ParseException(
        'That export was written by a newer version of DailyValo '
        '(format $version). Update the app and try again.',
      );
    }

    final Object? list = raw['entries'];
    if (list is! List) {
      throw const ParseException('That export has no entries in it.');
    }

    final List<WishlistEntry> entries = list
        .whereType<Map<String, dynamic>>()
        .map(WishlistEntry.fromJson)
        // A row with no uuid cannot be matched against a shop, so it would sit
        // in the list doing nothing.
        .where((WishlistEntry e) => e.skinUuid.isNotEmpty)
        .toList(growable: false);

    if (entries.isEmpty) {
      throw const ParseException('That export contains no usable entries.');
    }

    return WishlistTransfer(
      entries: entries,
      exportedAt:
          DateTime.tryParse(raw['exportedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// What an import did.
class ImportResult {
  const ImportResult({required this.added, required this.alreadyPresent});

  final int added;

  /// Entries already on the list. Merged rather than duplicated, and reported
  /// so "nothing happened" is distinguishable from "nothing needed to happen".
  final int alreadyPresent;

  int get total => added + alreadyPresent;

  String get summary {
    if (added == 0) {
      return alreadyPresent == 1
          ? 'That skin was already on your wishlist.'
          : 'All $alreadyPresent skins were already on your wishlist.';
    }
    final String addedPart =
        '$added ${added == 1 ? 'skin' : 'skins'} added';
    if (alreadyPresent == 0) return '$addedPart.';
    return '$addedPart, $alreadyPresent already there.';
  }
}
