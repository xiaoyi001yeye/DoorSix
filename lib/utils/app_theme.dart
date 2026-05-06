import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const background = Color(0xFF10201C);
  static const tableGreen = Color(0xFF17624F);
  static const tableDark = Color(0xFF0B332B);
  static const panel = Color(0xFF172B31);
  static const panelLight = Color(0xFF203A42);
  static const teamGold = Color(0xFFF4C45B);
  static const teamCyan = Color(0xFF4CC9F0);
  static const cardWhite = Color(0xFFF7F2E8);
  static const textPrimary = Color(0xFFF6F1E7);
  static const textSecondary = Color(0xFFAFC1BD);
  static const danger = Color(0xFFE85D5A);
  static const success = Color(0xFF79D98B);

  static void setSystemUi() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  static ThemeData get theme {
    setSystemUi();
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: teamGold,
        primary: teamGold,
        secondary: teamCyan,
        surface: panel,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textSecondary,
          height: 1.35,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: textPrimary,
          side: const BorderSide(color: Color(0x5579D98B)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
