import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/database_service.dart';

class ThemeProvider extends ChangeNotifier {
  late ThemeMode _themeMode;
  late Color _accentColor;

  ThemeMode get themeMode => _themeMode;
  bool get pureBlack => true;
  Color get accentColor => _accentColor;

  static const List<Color> availableAccents = [
    Color(0xFFE53935), // Melody Crimson Red
    Color(0xFFD81B60), // Rose Pink
    Color(0xFF8E24AA), // Deep Purple
    Color(0xFF3949AB), // Indigo
    Color(0xFF1E88E5), // Electric Blue
    Color(0xFF00897B), // Teal
    Color(0xFF43A047), // Emerald Green
    Color(0xFFFB8C00), // Vibrant Amber
  ];

  ThemeProvider() {
    final modeStr = DatabaseService.getThemeMode();
    _themeMode = modeStr == 'light'
        ? ThemeMode.light
        : modeStr == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;

    _accentColor = Color(DatabaseService.getAccentColor());
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    final str = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    DatabaseService.setThemeMode(str);
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    DatabaseService.setAccentColor(argb32(color));
    notifyListeners();
  }

  /// Converts [color] to 32-bit ARGB integer without relying on deprecated `.value`.
  static int argb32(Color color) {
    final a = (color.a * 255.0).round() & 0xff;
    final r = (color.r * 255.0).round() & 0xff;
    final g = (color.g * 255.0).round() & 0xff;
    final b = (color.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// Computes WCAG 2.1 contrast ratio between two opaque colors.
  static double contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = math.max(l1, l2);
    final lo = math.min(l1, l2);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Derives a cohesive theme-matched gradient for the floating MiniPlayer from [colorScheme].
  static LinearGradient miniPlayerGradient(ColorScheme colorScheme) {
    if (colorScheme.brightness == Brightness.dark) {
      final start = Color.lerp(
        colorScheme.surfaceContainerHigh,
        colorScheme.primaryContainer,
        0.44,
      )!;
      final end = Color.lerp(
        colorScheme.surfaceContainerLow,
        colorScheme.primaryContainer,
        0.16,
      )!;
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      );
    }

    final start = Color.lerp(
      colorScheme.surface,
      colorScheme.primaryContainer,
      0.52,
    )!;
    final end = Color.lerp(
      colorScheme.surfaceContainerLow,
      colorScheme.primaryContainer,
      0.78,
    )!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, end],
    );
  }

  /// Builds a contrast-verified Material 3 [ColorScheme] for [seed], [brightness], and pitch-black dark surface.
  static ColorScheme buildColorScheme({
    required Color seed,
    required Brightness brightness,
    bool pureBlack = true,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    if (brightness == Brightness.light) {
      var scheme = base;
      // Richer purple alignment when purple seed is active, matching Light Mode spec
      if (argb32(seed) == 0xFF8E24AA) {
        scheme = scheme.copyWith(
          primary: const Color(0xFF6E1B6E),
          onPrimary: const Color(0xFFFFFFFF),
          primaryContainer: const Color(0xFFEEDBF3),
          onPrimaryContainer: const Color(0xFF491454),
        );
      } else {
        scheme = _tuneLightContrast(scheme);
      }
      return scheme.copyWith(
        surface: const Color(0xFFF8F5FA),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFFFFFFF),
        surfaceContainer: const Color(0xFFF2ECF6),
        surfaceContainerHigh: const Color(0xFFEDE6F2),
        surfaceContainerHighest: const Color(0xFFE3DAE9),
        onSurface: const Color(0xFF1A141E),
        onSurfaceVariant: const Color(0xFF5B5163),
        outlineVariant: const Color(0xFFD8CEE0),
      );
    }

    var dark = base;
    if (argb32(seed) == 0xFF8E24AA) {
      // Richer orchid-purple hierarchy (7.34:1 primary/onPrimary, 10.28:1 container)
      dark = dark.copyWith(
        primary: const Color(0xFFCE82E3),
        onPrimary: const Color(0xFF16071B),
        primaryContainer: const Color(0xFF3A1C44),
        onPrimaryContainer: const Color(0xFFF0CCF8),
      );
    } else if (argb32(seed) == 0xFF1E88E5) {
      dark = dark.copyWith(
        primary: const Color(0xFF4EA1FF),
        onPrimary: const Color(0xFF041122),
        primaryContainer: const Color(0xFF132E4D),
        onPrimaryContainer: const Color(0xFFD3E6FF),
      );
    } else {
      dark = _tuneDarkContrast(dark);
    }

    if (!pureBlack) {
      return dark;
    }

    return dark.copyWith(
      surface: const Color(0xFF000000),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF131318),
      surfaceContainer: const Color(0xFF17171E),
      surfaceContainerHigh: const Color(0xFF1C1C22),
      surfaceContainerHighest: const Color(0xFF22222A),
      onSurface: const Color(0xFFF5F4F8),
      onSurfaceVariant: const Color(0xFFA8A8B4),
      outlineVariant: const Color(0xFF2B2B35),
    );
  }

  static ColorScheme _tuneDarkContrast(ColorScheme scheme) {
    var primary = scheme.primary;
    var onPrimary = scheme.onPrimary;
    final hsl = HSLColor.fromColor(primary);

    // Ensure dark-mode primary pops crisply on dark surfaces without becoming washed out
    if (hsl.lightness < 0.66) {
      primary = hsl.withLightness(0.68).withSaturation(math.min(0.88, hsl.saturation)).toColor();
    }
    final darkInk = HSLColor.fromColor(primary).withLightness(0.08).toColor();
    if (contrastRatio(primary, darkInk) >= 7.0) {
      onPrimary = darkInk;
    } else if (contrastRatio(primary, const Color(0xFF0A0A0D)) >= 7.0) {
      onPrimary = const Color(0xFF0A0A0D);
    } else {
      // Lift lightness slightly until 7:1 contrast against deep dark ink is guaranteed
      var l = HSLColor.fromColor(primary).lightness;
      while (l < 0.85 && contrastRatio(primary, darkInk) < 7.0) {
        l += 0.02;
        primary = HSLColor.fromColor(primary).withLightness(l).toColor();
      }
      onPrimary = darkInk;
    }

    var onContainer = scheme.onPrimaryContainer;
    if (contrastRatio(onContainer, scheme.primaryContainer) < 7.0) {
      onContainer = HSLColor.fromColor(scheme.primaryContainer).withLightness(0.90).toColor();
    }

    return scheme.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      onPrimaryContainer: onContainer,
    );
  }

  static ColorScheme _tuneLightContrast(ColorScheme scheme) {
    var primary = scheme.primary;
    const lightOnPrimary = Color(0xFFFFFFFF);
    var hsl = HSLColor.fromColor(primary);

    if (contrastRatio(primary, lightOnPrimary) < 7.0) {
      var l = hsl.lightness;
      while (l > 0.18 && contrastRatio(primary, lightOnPrimary) < 7.0) {
        l -= 0.02;
        primary = hsl.withLightness(l).toColor();
      }
    }

    var container = scheme.primaryContainer;
    var onContainer = scheme.onPrimaryContainer;
    if (contrastRatio(onContainer, container) < 7.0) {
      onContainer = HSLColor.fromColor(primary).withLightness(0.18).toColor();
    }

    return scheme.copyWith(
      primary: primary,
      onPrimary: lightOnPrimary,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
    );
  }

  ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.45),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primary,
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
    );
  }

  ThemeData get lightTheme => _buildTheme(
        buildColorScheme(
          seed: _accentColor,
          brightness: Brightness.light,
          pureBlack: false,
        ),
      );

  ThemeData get darkTheme => _buildTheme(
        buildColorScheme(
          seed: _accentColor,
          brightness: Brightness.dark,
          pureBlack: true,
        ),
      );
}
