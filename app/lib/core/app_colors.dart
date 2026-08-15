import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF0D0D0D);
  static const Color surfaceElevated = Color(0xFF141414);
  static const Color border = Color(0xFF1C1C1C);
  static const Color borderBright = Color(0xFF2A2A2A);

  // Accent
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentCyanDim = Color(0xFF00B8CC);
  static const Color accentMagenta = Color(0xFFFF006A);
  static const Color accentGold = Color(0xFFFFD60A);

  // Semantic
  static const Color goodGreen = Color(0xFF00E676);
  static const Color badRed = Color(0xFFFF3D57);
  static const Color warnOrange = Color(0xFFFF9100);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8C8C8C);
  static const Color textTertiary = Color(0xFF3A3A3A);

  // Glass
  static Color glass = Colors.white.withValues(alpha: 0.04);
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
  static Color glassBorderBright = Colors.white.withValues(alpha: 0.15);

  /// Panel fill for overlays sitting on the live camera preview, where the
  /// backdrop blur is switched off for performance. A 4% white wash is only
  /// legible because the blur flattens what is behind it; without the blur the
  /// panel needs to darken the video itself to keep text readable.
  static Color glassOverCamera = Colors.black.withValues(alpha: 0.55);
}
