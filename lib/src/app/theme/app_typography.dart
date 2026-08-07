import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale for the app.
///
/// No bundled font files — the platform's default sans (Roboto on Android) is
/// used with tightened tracking, which keeps the APK small and still reads like
/// a dashboard. Swap [fontFamily] for a bundled face (e.g. Tungsten/Inter) and
/// every screen follows.
abstract final class AppTypography {
  static const String? fontFamily = null;

  /// Wide-tracked uppercase used for section headers and stat captions.
  static const TextStyle overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: AppColors.textTertiary,
  );

  static TextTheme get textTheme => const TextTheme(
    displaySmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: AppColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 24,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: AppColors.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    titleSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 13,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
    bodyLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 15,
      height: 1.45,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 13.5,
      height: 1.45,
      color: AppColors.textSecondary,
    ),
    bodySmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 12,
      height: 1.4,
      color: AppColors.textTertiary,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: AppColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: AppColors.textSecondary,
    ),
    labelSmall: overline,
  );
}
