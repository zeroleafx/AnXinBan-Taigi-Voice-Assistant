import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Shared family and elder interface palette.
abstract final class AppColors {
  static const leaf = Color(0xFF297345);
  static const ocean = Color(0xFF236F80);
  static const teal = Color(0xFF54A86D);
  static const mutedTeal = Color(0xFF9CDFCD);
  static const celadon = Color(0xFFC5EEC8);
  static const bone = Color(0xFFFBFAF7);
  static const card = Color(0xFFFFFFFF);
  // Darker companion shade for readable text on the palette's light surfaces.
  static const ink = Color(0xFF263638);
  // Warm accent for recording and problems.
  static const coral = Color(0xFFE0583C);
  static const coralLight = Color(0xFFF28A5E);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.leaf).copyWith(
    primary: AppColors.leaf,
    onPrimary: Colors.white,
    secondary: AppColors.ocean,
    onSecondary: Colors.white,
    surface: AppColors.bone,
    onSurface: AppColors.ink,
    outline: AppColors.leaf,
    error: AppColors.coral,
  );
  return ThemeData(
    useMaterial3: true,
    // Bundle the Chinese font to avoid platform font substitution.
    fontFamily:
        !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS)
        ? 'NotoSansTC'
        : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bone,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bone,
      foregroundColor: AppColors.ink,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.card),
    cardTheme: const CardThemeData(color: AppColors.card),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
      ),
    ),
  );
}
