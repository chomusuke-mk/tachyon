import 'package:material_ui/material_ui.dart';

/// Color palette tokens and surface hierarchies used across Tachyon themes.
abstract final class TachyonColors {
  /// Default primary brand seed color (electric violet).
  static const Color electricVioletSeed = Color(0xFF7C4DFF);

  /// Default secondary brand seed color.
  static const Color secondarySeed = Color(0xFF64748B);

  /// Default tertiary accent seed color (cyber cyan).
  static const Color tertiarySeed = Color(0xFF00E5FF);

  /// Predefined accent color choices offered in theme customization settings.
  static const List<Color> predefinedAccentColors = [
    Color(0xFF7C4DFF), // Electric Violet (Default Brand)
    Color(0xFF3B82F6), // Royal Blue
    Color(0xFF00E5FF), // Cyber Cyan
    Color(0xFF10B981), // Emerald Green
    Color(0xFFEAB308), // Amber Gold
    Color(0xFFFF5722), // Sunset Orange
    Color(0xFFF43F5E), // Ruby Rose
    Color(0xFFD946EF), // Neon Magenta
  ];

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - Dark Theme (Default)
  // ---------------------------------------------------------------------------

  /// Base scaffold background color for the dark theme.
  static const Color darkCanvas = Color(0xFF0A0C10);

  /// Lowest-elevation container surface color for the dark theme.
  static const Color darkSurfaceLowest = Color(0xFF07080B);

  /// Low-elevation container surface color for the dark theme.
  static const Color darkSurfaceLow = Color(0xFF11141B);

  /// Standard container surface color for the dark theme.
  static const Color darkSurface = Color(0xFF171B24);

  /// High-elevation container surface color for the dark theme.
  static const Color darkSurfaceHigh = Color(0xFF1F2532);

  /// Highest-elevation container surface color for the dark theme.
  static const Color darkSurfaceHighest = Color(0xFF293142);

  /// Primary foreground text color for the dark and OLED themes.
  static const Color darkTextPrimary = Color(0xFFF1F5F9);

  /// Secondary foreground text color for the dark and OLED themes.
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  /// Muted tertiary text color for the dark theme.
  static const Color darkTextTertiary = Color(0xFF64748B);

  /// Subtle hairline border color for the dark theme.
  static const Color darkBorderSubtle = Color(0x1FFFFFFF);

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - True OLED Mode (#000000)
  // ---------------------------------------------------------------------------

  /// Pure black scaffold background color for the OLED theme.
  static const Color oledCanvas = Color(0xFF000000);

  /// Lowest-elevation pure black surface color for the OLED theme.
  static const Color oledSurfaceLowest = Color(0xFF000000);

  /// Low-elevation container surface color for the OLED theme.
  static const Color oledSurfaceLow = Color(0xFF07090C);

  /// Standard container surface color for the OLED theme.
  static const Color oledSurface = Color(0xFF0E1116);

  /// High-elevation container surface color for the OLED theme.
  static const Color oledSurfaceHigh = Color(0xFF151920);

  /// Highest-elevation container surface color for the OLED theme.
  static const Color oledSurfaceHighest = Color(0xFF1E232C);

  /// Subtle hairline border color for the OLED theme.
  static const Color oledBorderSubtle = Color(0x28FFFFFF);

  // ---------------------------------------------------------------------------
  // 5-Tier Surface Hierarchy - Light Theme
  // ---------------------------------------------------------------------------

  /// Base scaffold background color for the light theme.
  static const Color lightCanvas = Color(0xFFF8FAFC);

  /// Lowest-elevation container surface color for the light theme.
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);

  /// Low-elevation container surface color for the light theme.
  static const Color lightSurfaceLow = Color(0xFFF1F4F9);

  /// Standard container surface color for the light theme.
  static const Color lightSurface = Color(0xFFE8EEF5);

  /// High-elevation container surface color for the light theme.
  static const Color lightSurfaceHigh = Color(0xFFDFE6F0);

  /// Highest-elevation container surface color for the light theme.
  static const Color lightSurfaceHighest = Color(0xFFD3DDEB);

  /// Primary foreground text color for the light theme.
  static const Color lightTextPrimary = Color(0xFF0F172A);

  /// Secondary foreground text color for the light theme.
  static const Color lightTextSecondary = Color(0xFF475569);

  /// Muted tertiary text color for the light theme.
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  /// Subtle hairline border color for the light theme.
  static const Color lightBorderSubtle = Color(0x1F000000);
}

/// Responsive layout breakpoints and viewport size helpers.
abstract final class TachyonBreakpoints {
  /// Minimum viewport width in logical pixels considered a desktop layout.
  static const double desktopBreakpoint = 720.0;

  /// Returns whether the viewport width for [context] meets [desktopBreakpoint].
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  /// Returns whether the viewport width for [context] is below [desktopBreakpoint].
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < desktopBreakpoint;
}

/// Material 3 theme factory for dark, OLED, and light Tachyon appearances.
abstract final class TachyonTheme {
  /// Builds the dark [ThemeData] seeded from [seedColor].
  ///
  /// When [hasCustomBackground] is `true`, scaffold and app-bar backgrounds are
  /// made transparent and card/navigation surfaces become translucent.
  static ThemeData buildDarkTheme({
    Color seedColor = TachyonColors.electricVioletSeed,
    bool hasCustomBackground = false,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
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

    return _buildTheme(
      colorScheme,
      TachyonColors.darkBorderSubtle,
      hasCustomBackground: hasCustomBackground,
    );
  }

  /// Builds the pure-black OLED [ThemeData] seeded from [seedColor].
  ///
  /// When [hasCustomBackground] is `true`, scaffold and app-bar backgrounds are
  /// made transparent and card/navigation surfaces become translucent.
  static ThemeData buildOledTheme({
    Color seedColor = TachyonColors.electricVioletSeed,
    bool hasCustomBackground = false,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
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

    return _buildTheme(
      colorScheme,
      TachyonColors.oledBorderSubtle,
      hasCustomBackground: hasCustomBackground,
    );
  }

  /// Builds the light [ThemeData] seeded from [seedColor].
  ///
  /// When [hasCustomBackground] is `true`, scaffold and app-bar backgrounds are
  /// made transparent and card/navigation surfaces become translucent.
  static ThemeData buildLightTheme({
    Color seedColor = TachyonColors.electricVioletSeed,
    bool hasCustomBackground = false,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
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

    return _buildTheme(
      colorScheme,
      TachyonColors.lightBorderSubtle,
      hasCustomBackground: hasCustomBackground,
    );
  }

  /// Default dark [ThemeData] seeded with [TachyonColors.electricVioletSeed].
  static ThemeData get darkTheme => buildDarkTheme();

  /// Default pure-black OLED [ThemeData] seeded with [TachyonColors.electricVioletSeed].
  static ThemeData get oledTheme => buildOledTheme();

  /// Default light [ThemeData] seeded with [TachyonColors.electricVioletSeed].
  static ThemeData get lightTheme => buildLightTheme();

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

  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    Color rimBorder, {
    bool hasCustomBackground = false,
  }) {
    final textTheme = _createTextTheme(
      colorScheme.onSurface,
      colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          hasCustomBackground ? Colors.transparent : colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            hasCustomBackground ? Colors.transparent : colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: hasCustomBackground
            ? colorScheme.surfaceContainer.withValues(alpha: 0.70)
            : colorScheme.surfaceContainer,
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
        backgroundColor: hasCustomBackground
            ? colorScheme.surfaceContainerLow.withValues(alpha: 0.85)
            : colorScheme.surfaceContainerLow,
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
        backgroundColor: hasCustomBackground
            ? colorScheme.surfaceContainerLow.withValues(alpha: 0.85)
            : colorScheme.surfaceContainerLow,
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
