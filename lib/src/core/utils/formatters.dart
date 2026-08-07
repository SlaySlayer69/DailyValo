import 'package:intl/intl.dart';

/// Display helpers shared by the shop, night market and wishlist tabs.
abstract final class Formatters {
  static final NumberFormat _grouped = NumberFormat.decimalPattern('en_US');

  /// `1775` -> `1,775`
  static String points(int value) => _grouped.format(value);

  /// Countdown rendered as `13h 24m 09s`, dropping empty leading units.
  static String duration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final int days = d.inDays;
    final int hours = d.inHours % 24;
    final int minutes = d.inMinutes % 60;
    final int seconds = d.inSeconds % 60;

    final String h = hours.toString().padLeft(2, '0');
    final String m = minutes.toString().padLeft(2, '0');
    final String s = seconds.toString().padLeft(2, '0');

    if (days > 0) return '${days}d ${h}h ${m}m';
    if (hours > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  /// `SlaySlayer` + `161` -> `SlaySlayer#161`
  static String riotId(String gameName, String tagLine) =>
      tagLine.isEmpty ? gameName : '$gameName#$tagLine';

  /// `EEquippableCategory::Rifle` -> `Rifle`
  static String enumTail(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final int i = raw.lastIndexOf('::');
    return i == -1 ? raw : raw.substring(i + 2);
  }

  /// `IRON 1` -> `Iron 1`
  static String titleCase(String raw) {
    return raw
        .toLowerCase()
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .map((String w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
