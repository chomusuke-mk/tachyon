import 'package:flutter/material.dart';

abstract final class TachyonColors {
  // Brand Seeds
  static const Color electricVioletSeed = Color(0xFF7C4DFF);
  static const Color secondarySeed = Color(0xFF64748B);
  static const Color tertiarySeed = Color(0xFF00E5FF);

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - Dark Theme (Default)
  // ---------------------------------------------------------------------------
  static const Color darkCanvas = Color(0xFF0A0C10);
  static const Color darkSurfaceLowest = Color(0xFF07080B);
  static const Color darkSurfaceLow = Color(0xFF11141B);
  static const Color darkSurface = Color(0xFF171B24);
  static const Color darkSurfaceHigh = Color(0xFF1F2532);
  static const Color darkSurfaceHighest = Color(0xFF293142);

  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);
  static const Color darkBorderSubtle = Color(0x1FFFFFFF);

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - True OLED Mode (#000000)
  // ---------------------------------------------------------------------------
  static const Color oledCanvas = Color(0xFF000000);
  static const Color oledSurfaceLowest = Color(0xFF000000);
  static const Color oledSurfaceLow = Color(0xFF07090C);
  static const Color oledSurface = Color(0xFF0E1116);
  static const Color oledSurfaceHigh = Color(0xFF151920);
  static const Color oledSurfaceHighest = Color(0xFF1E232C);
  static const Color oledBorderSubtle = Color(0x28FFFFFF);

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - Light Theme
  // ---------------------------------------------------------------------------
  static const Color lightCanvas = Color(0xFFF8FAFC);
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFF1F4F9);
  static const Color lightSurface = Color(0xFFE8EEF5);
  static const Color lightSurfaceHigh = Color(0xFFDFE6F0);
  static const Color lightSurfaceHighest = Color(0xFFD3DDEB);

  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  static const Color lightBorderSubtle = Color(0x1F000000);
}

abstract final class TachyonBreakpoints {
  /// Tablet / Desktop threshold
  static const double desktopBreakpoint = 720.0;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < desktopBreakpoint;
}

abstract final class TachyonTheme {
  /// Dark Theme (Primary Default)
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TachyonColors.electricVioletSeed,
      brightness: Brightness.dark,
      surface: TachyonColors.darkCanvas,
      surfaceContainerLowest: TachyonColors.darkSurfaceLowest,
      surfaceContainerLow: TachyonColors.darkSurfaceLow,
      surfaceContainer: TachyonColors.darkSurface,
      surfaceContainerHigh: TachyonColors.darkSurfaceHigh,
      surfaceContainerHighest: TachyonColors.darkSurfaceHighest,
      onSurface: TachyonColors.darkTextPrimary,
      onSurfaceVariant: TachyonColors.darkTextSecondary,
      outline: TachyonColors.darkBorderSubtle,
    );

    return _buildTheme(colorScheme, TachyonColors.darkBorderSubtle);
  }

  /// True OLED Pure Black Theme
  static ThemeData get oledTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TachyonColors.electricVioletSeed,
      brightness: Brightness.dark,
      surface: TachyonColors.oledCanvas,
      surfaceContainerLowest: TachyonColors.oledSurfaceLowest,
      surfaceContainerLow: TachyonColors.oledSurfaceLow,
      surfaceContainer: TachyonColors.oledSurface,
      surfaceContainerHigh: TachyonColors.oledSurfaceHigh,
      surfaceContainerHighest: TachyonColors.oledSurfaceHighest,
      onSurface: TachyonColors.darkTextPrimary,
      onSurfaceVariant: TachyonColors.darkTextSecondary,
      outline: TachyonColors.oledBorderSubtle,
    );

    return _buildTheme(colorScheme, TachyonColors.oledBorderSubtle);
  }

  /// Light Theme
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TachyonColors.electricVioletSeed,
      brightness: Brightness.light,
      surface: TachyonColors.lightCanvas,
      surfaceContainerLowest: TachyonColors.lightSurfaceLowest,
      surfaceContainerLow: TachyonColors.lightSurfaceLow,
      surfaceContainer: TachyonColors.lightSurface,
      surfaceContainerHigh: TachyonColors.lightSurfaceHigh,
      surfaceContainerHighest: TachyonColors.lightSurfaceHighest,
      onSurface: TachyonColors.lightTextPrimary,
      onSurfaceVariant: TachyonColors.lightTextSecondary,
      outline: TachyonColors.lightBorderSubtle,
    );

    return _buildTheme(colorScheme, TachyonColors.lightBorderSubtle);
  }

  static TextTheme _createTextTheme(Color onSurface, Color onSurfaceVariant) {
    const tabularFeatures = [FontFeature.tabularFigures()];

    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: onSurface,
        fontFeatures: tabularFeatures,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: onSurface,
        fontFeatures: tabularFeatures,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: onSurfaceVariant,
        fontFeatures: tabularFeatures,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: onSurfaceVariant,
        fontFeatures: tabularFeatures,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: onSurface,
        fontFeatures: tabularFeatures,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: onSurfaceVariant,
        fontFeatures: tabularFeatures,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: onSurfaceVariant,
        fontFeatures: tabularFeatures,
      ),
    );
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Color rimBorder) {
    final textTheme = _createTextTheme(
      colorScheme.onSurface,
      colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: rimBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: rimBorder, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: rimBorder, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: rimBorder, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onPrimaryContainer,
          size: 24,
        ),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: 24,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        trackHeight: 4.0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: rimBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: rimBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
