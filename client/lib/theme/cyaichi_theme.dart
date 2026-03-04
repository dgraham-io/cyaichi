import 'package:flutter/material.dart';

class CyaichiTheme {
  static const Color background = Color(0xFF0E182A);
  static const Color surface = Color(0xFF162438);
  static const Color surfaceVariant = Color(0xFF1D304B);
  static const Color primary = Color(0xFF38DCE9);
  static const Color secondary = Color(0xFF2288AF);
  static const Color outline = Color(0xFF1A5479);
  static const Color onBackground = Color(0xFFBDF8F8);

  static final ColorScheme _darkColorScheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: background,
    secondary: secondary,
    onSecondary: onBackground,
    tertiary: Color(0xFF4AB6D6),
    onTertiary: background,
    error: Color(0xFFFF6B8A),
    onError: Color(0xFF290513),
    surface: surface,
    onSurface: onBackground,
    surfaceContainerHighest: surfaceVariant,
    onSurfaceVariant: Color(0xFF8EDBE4),
    outline: outline,
    outlineVariant: Color(0xFF21456A),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFE7FCFE),
    onInverseSurface: background,
    inversePrimary: Color(0xFF0D97AE),
  );

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: onBackground),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }
}
