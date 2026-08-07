import 'package:flutter/material.dart';

/// The DailyValo palette: near-black canvas, graphite surfaces, one loud red.
///
/// Rarity colours are *not* here — those come from the live content API
/// (`ContentTier.highlightColor`) so the app stays correct when Riot adds a
/// new tier.
abstract final class AppColors {
  /// Page background. Deliberately not pure black so elevation reads.
  static const Color background = Color(0xFF0B0C0F);

  /// Slightly lifted background used behind scrollable content.
  static const Color backgroundElevated = Color(0xFF101216);

  /// Default card / sheet fill.
  static const Color surface = Color(0xFF15181D);

  /// Card fill one step up — chips, nested tiles, image placeholders.
  static const Color surfaceVariant = Color(0xFF1D2128);

  /// Hairlines and card outlines.
  static const Color border = Color(0xFF262B33);
  static const Color borderStrong = Color(0xFF39404A);

  /// Valorant red. Used sparingly: active tab, primary action, price accent.
  static const Color accent = Color(0xFFFF4655);
  static const Color accentPressed = Color(0xFFD8323F);

  /// 12% red — glow behind selected cards and icon chips.
  static const Color accentSubtle = Color(0x1FFF4655);

  static const Color textPrimary = Color(0xFFECEFF3);
  static const Color textSecondary = Color(0xFF98A0AC);
  static const Color textTertiary = Color(0xFF5F6773);

  static const Color success = Color(0xFF35D07F);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF5A5F);

  /// Night Market discount badge.
  static const Color discount = Color(0xFF35D07F);

  /// Parses the `RRGGBBAA` hex strings that valorant-api.com returns for
  /// content tiers and competitive ranks. Returns [fallback] on anything
  /// unexpected so a malformed colour can never crash a list.
  static Color fromRgbaHex(String? hex, {Color fallback = borderStrong}) {
    if (hex == null) return fallback;
    final String cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 8 && cleaned.length != 6) return fallback;
    final int? rgba = int.tryParse(cleaned, radix: 16);
    if (rgba == null) return fallback;
    if (cleaned.length == 6) return Color(0xFF000000 | rgba);
    // RRGGBBAA -> AARRGGBB
    final int alpha = rgba & 0xFF;
    final int rgb = (rgba >> 8) & 0xFFFFFF;
    return Color((alpha << 24) | rgb);
  }
}
