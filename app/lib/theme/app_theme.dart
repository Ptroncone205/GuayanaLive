import 'package:flutter/material.dart';

class AppTheme {
  // Core palette
  static const Color lightGreen = Color(0xFFb6d693);
  static const Color darkGreen = Color(0xFF88B84B);

  // Light theme colors
  static const Color lightBackground = Color(0xFFF5F5F2);
  static const Color lightSurface = Color(0xFFE7E9E2);
  static const Color lightText = Color(0xFF2F3828);
  static const Color lightSubText = Color(0xFF7A8075);

  // Dark theme colors
  static const Color darkBackground = Color(0xFF10110F);
  static const Color darkSurface = Color(0xFF3E4937);
  static const Color darkText = Color(0xFFF1F3EC);
  static const Color darkSubText = Color(0xFFADB3A6);

  ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: lightGreen,
      secondary: darkGreen,
      surface: lightSurface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: lightGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: const TextStyle(color: lightSubText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: lightText,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: lightSubText,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: lightText,
          fontWeight: FontWeight.bold,
        ),
      ),

      dividerColor: Colors.black12,
    );
  }

  ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      primary: lightGreen,
      secondary: darkSurface,
      surface: darkSurface,
      onPrimary: darkGreen,
      onSecondary: darkText,
      onSurface: darkText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: darkText),
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightGreen,
          foregroundColor: darkGreen,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: const TextStyle(color: darkSubText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: darkText,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: darkSubText,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.bold,
        ),
      ),

      dividerColor: Colors.white12,
    );
  }
}