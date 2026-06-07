import 'package:flutter/material.dart';

class NoTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}

class AppTheme {
  // ══════════════════════════════════════════
  //  BRAND COLORS (FNB Warm Palette)
  // ══════════════════════════════════════════
  static const Color brandOrange = Color(0xFFE65100);
  static const Color brandAmber = Color(0xFFFFB74D);
  static const Color brandBrown = Color(0xFF3E2723);
  static const Color brandCream = Color(0xFFFFF8F0);

  // Sidebar colors (dark sidebar for premium feel)
  static const Color sidebarDark = Color(0xFF2C1B14);
  static const Color sidebarDarkAlt = Color(0xFF1A1210);
  static const Color sidebarItemActive = Color(0x33FFB74D); // amber 20%
  static const Color sidebarItemHover = Color(0x14FFB74D); // amber 8%
  static const Color sidebarText = Color(0xFFE0D6CC);
  static const Color sidebarTextMuted = Color(0xFF9C8A7C);

  // ══════════════════════════════════════════
  //  LIGHT THEME — "Warm Café"
  // ══════════════════════════════════════════
  static ThemeData get lightTheme {
    const primary = Color(0xFFE65100);
    const onPrimary = Color(0xFFFFFFFF);
    const primaryContainer = Color(0xFFFFE0B2);
    const onPrimaryContainer = Color(0xFF4E1C00);

    const secondary = Color(0xFF2E7D32);
    const onSecondary = Color(0xFFFFFFFF);
    const secondaryContainer = Color(0xFFC8E6C9);
    const onSecondaryContainer = Color(0xFF1B5E20);

    const tertiary = Color(0xFF6D4C41);
    const onTertiary = Color(0xFFFFFFFF);
    const tertiaryContainer = Color(0xFFEFEBE9);
    const onTertiaryContainer = Color(0xFF3E2723);

    const error = Color(0xFFD32F2F);
    const onError = Color(0xFFFFFFFF);
    const errorContainer = Color(0xFFFFCDD2);
    const onErrorContainer = Color(0xFF7F1D1D);

    const surface = Color(0xFFF5F0E8);
    const surfaceDim = Color(0xFFE0D8CE);
    const surfaceBright = Color(0xFFFAF6F0);
    const surfaceContainerLowest = Color(0xFFFCF8F2);
    const surfaceContainerLow = Color(0xFFF2EAE0);
    const surfaceContainer = Color(0xFFEAE2D8);
    const surfaceContainerHigh = Color(0xFFE2DAD0);
    const surfaceContainerHighest = Color(0xFFDAD2C8);

    const onSurface = Color(0xFF1A1210);
    const onSurfaceVariant = Color(0xFF5D4E44);
    const outline = Color(0xFF9C8A7C);
    const outlineVariant = Color(0xFFE0D6CC);

    return ThemeData(
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: surface,
      useMaterial3: true,
      fontFamily: 'Inter',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: NoTransitionsBuilder(),
          TargetPlatform.iOS: NoTransitionsBuilder(),
          TargetPlatform.windows: NoTransitionsBuilder(),
          TargetPlatform.macOS: NoTransitionsBuilder(),
          TargetPlatform.linux: NoTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF3E2723),
        selectedItemColor: brandAmber,
        unselectedItemColor: Color(0xFF9C8A7C),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineVariant, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: surfaceBright,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primaryContainer,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: brandBrown,
        contentTextStyle: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
      ),
      dividerTheme: const DividerThemeData(color: outlineVariant, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: outlineVariant, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: error, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: error, width: 2)),
        hintStyle: const TextStyle(color: outline),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: onSurfaceVariant,
        indicatorColor: primary,
      ),
    );
  }

  // ══════════════════════════════════════════
  //  DARK THEME — "Night Kitchen"
  // ══════════════════════════════════════════
  static ThemeData get darkTheme {
    const primary = Color(0xFFFFB74D);
    const onPrimary = Color(0xFF3E2723);
    const primaryContainer = Color(0xFF4E342E);
    const onPrimaryContainer = Color(0xFFFFE0B2);

    const secondary = Color(0xFF81C784);
    const onSecondary = Color(0xFF1B5E20);
    const secondaryContainer = Color(0xFF2E7D32);
    const onSecondaryContainer = Color(0xFFC8E6C9);

    const tertiary = Color(0xFFBCAAA4);
    const onTertiary = Color(0xFF3E2723);
    const tertiaryContainer = Color(0xFF4E342E);
    const onTertiaryContainer = Color(0xFFEFEBE9);

    const error = Color(0xFFEF9A9A);
    const onError = Color(0xFF7F1D1D);
    const errorContainer = Color(0xFF5D1515);
    const onErrorContainer = Color(0xFFFFCDD2);

    const surface = Color(0xFF1A1210);
    const surfaceDim = Color(0xFF120E0C);
    const surfaceBright = Color(0xFF2C1F1A);
    const surfaceContainerLowest = Color(0xFF120E0C);
    const surfaceContainerLow = Color(0xFF211916);
    const surfaceContainerHighest = Color(0xFF3D302A);
    const surfaceContainer = Color(0xFF2C2320);
    const surfaceContainerHigh = Color(0xFF352A24);

    const onSurface = Color(0xFFEDE0D4);
    const onSurfaceVariant = Color(0xFFA89888);
    const outline = Color(0xFF6D5D50);
    const outlineVariant = Color(0xFF3D302A);

    return ThemeData(
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: surface,
      useMaterial3: true,
      fontFamily: 'Inter',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: NoTransitionsBuilder(),
          TargetPlatform.iOS: NoTransitionsBuilder(),
          TargetPlatform.windows: NoTransitionsBuilder(),
          TargetPlatform.macOS: NoTransitionsBuilder(),
          TargetPlatform.linux: NoTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceBright,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceBright,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineVariant, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: surfaceContainerHigh,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primaryContainer,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: surfaceContainerHigh,
        contentTextStyle: const TextStyle(color: onSurface, fontFamily: 'Inter'),
      ),
      dividerTheme: const DividerThemeData(color: outlineVariant, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: outlineVariant, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: error, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: error, width: 2)),
        hintStyle: const TextStyle(color: outline),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: onSurfaceVariant,
        indicatorColor: primary,
      ),
    );
  }
}
