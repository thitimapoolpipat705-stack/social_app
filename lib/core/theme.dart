/// lib/core/theme.dart
/// Modern color theme configuration for MindSocial app
import 'package:flutter/material.dart';

/// Define the modern color palette
class AppColors {
  // Primary color: Modern Indigo - professional & vibrant
  static const Color primary = Color(0xFF6366F1);
  
  // Secondary: Modern cyan/teal - complements primary
  static const Color secondary = Color(0xFF0EA5E9);
  
  // Accent: Gradient-inspired warm accent
  static const Color accent = Color(0xFFEC4899);
  
  // Success: Modern green
  static const Color success = Color(0xFF10B981);
  
  // Warning: Modern orange
  static const Color warning = Color(0xFFF59E0B);
  
  // Error: Modern red
  static const Color error = Color(0xFFEF4444);
  
  // Neutral grays
  static const Color surfaceLight = Color(0xFFFAFAFA);
  static const Color surfaceDark = Color(0xFFF3F4F6);
  static const Color onSurface = Color(0xFF1F2937);
  static const Color outline = Color(0xFFD1D5DB);
}

/// Modern theme data builder
ThemeData buildModernTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.primary,
    brightness: Brightness.light,
    
    // Smooth page transitions
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    
    // Enhanced AppBar styling
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: AppColors.surfaceLight,
      foregroundColor: AppColors.onSurface,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
    ),
    
    // Enhanced FloatingActionButton
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    
    // Enhanced Button styling
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
      ),
    ),
    
    // Enhanced Card styling
    cardTheme: CardTheme(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: AppColors.surfaceLight,
    ),
  );
}
