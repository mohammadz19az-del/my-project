import 'package:flutter/material.dart';

/// Cyberpunk control-center palette (see design system in the project spec).
abstract final class AppColors {
  // Dark backgrounds / surfaces
  static const Color bg0 = Color(0xFF080B14);
  static const Color bg1 = Color(0xFF0D1220);
  static const Color bg2 = Color(0xFF131B2B);
  static const Color surface = Color(0xFF151E30);
  static const Color surface2 = Color(0xFF1B263B);

  // Light counterparts
  static const Color lightBg = Color(0xFFF2F5FA);
  static const Color lightSurface = Color(0xFFFFFFFF);

  // Accents
  static const Color cyan = Color(0xFF22D3EE);
  static const Color blue = Color(0xFF3B82F6);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
}
