import 'dart:collection';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../utils/thumbnail_utils.dart';

/// Controls dark and light canvas elevation character alongside accent color.
enum ThemeSurfaceStyle {
  oledBlack(
    'OLED Black',
    'Pure black dark & crisp white light',
  ),
  materialNeutral(
    'Material Neutral',
    'Charcoal dark & soft off-white',
  ),
  tinted(
    'Tinted',
    'Accent-washed dark & pastel light',
  ),
  highContrast(
    'High Contrast',
    'Sharper borders & highest ink contrast',
  );

  final String label;
  final String description;

  const ThemeSurfaceStyle(this.label, this.description);
}

/// A named curated accent seed swatch.
@immutable
class AccentPreset {
  final String name;
  final Color color;

  const AccentPreset(this.name, this.color);
}

/// A one-tap cohesive combination of theme mode, surface style, and accent.
@immutable
class ThemePreset {
  final String id;
  final String name;
  final ThemeMode themeMode;
  final ThemeSurfaceStyle surfaceStyle;
  final Color accentColor;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.themeMode,
    required this.surfaceStyle,
    required this.accentColor,
  });
}

typedef AdaptiveColorSchemeLoader = Future<ColorScheme> Function(
  ImageProvider provider,
  Brightness brightness,
);

class ThemeProvider extends ChangeNotifier {
  static const int maxAdaptiveCacheEntries = 64;
  static const Color monochromeAccentColor = Color(0xFF71717A);

  static const List<AccentPreset> accentPresets = [
    AccentPreset('Crimson Red', Color(0xFFE53935)),
    AccentPreset('Rose Coral', Color(0xFFD81B60)),
    AccentPreset('Sunset Orange', Color(0xFFF4511E)),
    AccentPreset('Amber Gold', Color(0xFFFB8C00)),
    AccentPreset('Warm Sand', Color(0xFFC89B6E)),
    AccentPreset('Lime Sage', Color(0xFF7CB342)),
    AccentPreset('Emerald', Color(0xFF43A047)),
    AccentPreset('Teal', Color(0xFF00897B)),
    AccentPreset('Ice Cyan', Color(0xFF00ACC1)),
    AccentPreset('Sky Blue', Color(0xFF1E88E5)),
    AccentPreset('Cobalt', Color(0xFF2962FF)),
    AccentPreset('Indigo', Color(0xFF3949AB)),
    AccentPreset('Royal Purple', Color(0xFF8E24AA)),
    AccentPreset('Orchid Magenta', Color(0xFFC026D3)),
    AccentPreset('Slate Steel', Color(0xFF607D8B)),
    AccentPreset('Monochrome', monochromeAccentColor),
  ];

  static const List<Color> availableAccents = [
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFFF4511E),
    Color(0xFFFB8C00),
    Color(0xFFC89B6E),
    Color(0xFF7CB342),
    Color(0xFF43A047),
    Color(0xFF00897B),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF2962FF),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFFC026D3),
    Color(0xFF607D8B),
    monochromeAccentColor,
  ];

  static const List<ThemePreset> curatedPresets = [
    ThemePreset(
      id: 'oled_crimson',
      name: 'OLED Crimson',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.oledBlack,
      accentColor: Color(0xFFE53935),
    ),
    ThemePreset(
      id: 'midnight_indigo',
      name: 'Midnight Indigo',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.tinted,
      accentColor: Color(0xFF3949AB),
    ),
    ThemePreset(
      id: 'forest_night',
      name: 'Forest Night',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.tinted,
      accentColor: Color(0xFF43A047),
    ),
    ThemePreset(
      id: 'velvet_wine',
      name: 'Velvet Wine',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.tinted,
      accentColor: Color(0xFFD81B60),
    ),
    ThemePreset(
      id: 'warm_espresso',
      name: 'Warm Espresso',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.tinted,
      accentColor: Color(0xFFC89B6E),
    ),
    ThemePreset(
      id: 'nordic_slate',
      name: 'Nordic Slate',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.materialNeutral,
      accentColor: Color(0xFF607D8B),
    ),
    ThemePreset(
      id: 'monochrome_ink',
      name: 'Monochrome Ink',
      themeMode: ThemeMode.dark,
      surfaceStyle: ThemeSurfaceStyle.highContrast,
      accentColor: monochromeAccentColor,
    ),
    ThemePreset(
      id: 'soft_paper',
      name: 'Soft Paper',
      themeMode: ThemeMode.light,
      surfaceStyle: ThemeSurfaceStyle.tinted,
      accentColor: Color(0xFFC89B6E),
    ),
  ];

  late ThemeMode _themeMode;
  late ThemeSurfaceStyle _surfaceStyle;
  late Color _accentColor;
  late bool _adaptivePlayerTint;

  final AdaptiveColorSchemeLoader _adaptiveSchemeLoader;
  final LinkedHashMap<String, ColorScheme> _adaptiveSchemeCache =
      LinkedHashMap<String, ColorScheme>();
  final Map<String, Future<ColorScheme?>> _inFlightAdaptiveRequests = {};

  ThemeMode get themeMode => _themeMode;
  ThemeSurfaceStyle get surfaceStyle => _surfaceStyle;
  bool get pureBlack => _surfaceStyle == ThemeSurfaceStyle.oledBlack;
  Color get accentColor => _accentColor;
  bool get adaptivePlayerTint => _adaptivePlayerTint;

  @visibleForTesting
  int get adaptiveCacheLength => _adaptiveSchemeCache.length;

  ThemePreset? get activePreset {
    final activeArgb = argb32(_accentColor);
    for (final preset in curatedPresets) {
      if (preset.themeMode == _themeMode &&
          preset.surfaceStyle == _surfaceStyle &&
          argb32(preset.accentColor) == activeArgb) {
        return preset;
      }
    }
    return null;
  }

  ThemeProvider({AdaptiveColorSchemeLoader? adaptiveSchemeLoader})
      : _adaptiveSchemeLoader =
            adaptiveSchemeLoader ?? _defaultAdaptiveSchemeLoader {
    final modeStr = DatabaseService.getThemeMode();
    _themeMode = modeStr == 'light'
        ? ThemeMode.light
        : modeStr == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;

    final storedStyle = DatabaseService.getStoredSurfaceStyle();
    if (storedStyle != null) {
      _surfaceStyle = _parseSurfaceStyle(storedStyle);
    } else if (DatabaseService.hasExplicitPureBlack() &&
        !DatabaseService.getPureBlack()) {
      // Preserve explicit non-AMOLED preference from older versions on first upgrade.
      _surfaceStyle = ThemeSurfaceStyle.materialNeutral;
    } else {
      _surfaceStyle = ThemeSurfaceStyle.oledBlack;
    }

    _accentColor = Color(DatabaseService.getAccentColor());
    _adaptivePlayerTint = DatabaseService.getAdaptivePlayerTint();
  }

  static Future<ColorScheme> _defaultAdaptiveSchemeLoader(
    ImageProvider provider,
    Brightness brightness,
  ) {
    return ColorScheme.fromImageProvider(
      provider: provider,
      brightness: brightness,
    );
  }

  static ThemeSurfaceStyle _parseSurfaceStyle(String raw) {
    for (final style in ThemeSurfaceStyle.values) {
      if (style.name == raw) return style;
    }
    return ThemeSurfaceStyle.oledBlack;
  }

  static bool isMonochromeSeed(Color seed) {
    return argb32(seed) == argb32(monochromeAccentColor);
  }

  static String accentNameFor(Color color) {
    final target = argb32(color);
    for (final preset in accentPresets) {
      if (argb32(preset.color) == target) return preset.name;
    }
    return 'Custom Accent';
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

  void setSurfaceStyle(ThemeSurfaceStyle style) {
    _surfaceStyle = style;
    DatabaseService.setSurfaceStyle(style.name);
    DatabaseService.setPureBlack(style == ThemeSurfaceStyle.oledBlack);
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    DatabaseService.setAccentColor(argb32(color));
    notifyListeners();
  }

  void applyPreset(ThemePreset preset) {
    _themeMode = preset.themeMode;
    _surfaceStyle = preset.surfaceStyle;
    _accentColor = preset.accentColor;

    final modeStr = preset.themeMode == ThemeMode.light
        ? 'light'
        : preset.themeMode == ThemeMode.dark
            ? 'dark'
            : 'system';
    DatabaseService.setThemeMode(modeStr);
    DatabaseService.setSurfaceStyle(preset.surfaceStyle.name);
    DatabaseService.setPureBlack(
      preset.surfaceStyle == ThemeSurfaceStyle.oledBlack,
    );
    DatabaseService.setAccentColor(argb32(preset.accentColor));
    notifyListeners();
  }

  void setAdaptivePlayerTint(bool enabled) {
    _adaptivePlayerTint = enabled;
    DatabaseService.setAdaptivePlayerTint(enabled);
    notifyListeners();
  }

  @visibleForTesting
  void clearAdaptiveCache() {
    _adaptiveSchemeCache.clear();
    _inFlightAdaptiveRequests.clear();
  }

  /// Resolves a subtly artwork-tinted [ColorScheme] for `PlayerScreen`, falling
  /// back to null whenever Adaptive Player Tint is off or artwork cannot load.
  Future<ColorScheme?> resolveAdaptivePlayerScheme({
    required String thumbnailUrl,
    required ColorScheme baseScheme,
  }) async {
    if (!_adaptivePlayerTint) return null;

    final trimmed = thumbnailUrl.trim();
    if (trimmed.isEmpty ||
        (!trimmed.startsWith('http://') && !trimmed.startsWith('https://'))) {
      return null;
    }

    final normalizedUrl = ThumbnailUtils.upgradeUrl(trimmed, size: 544);
    final cacheKey = '$normalizedUrl|${baseScheme.brightness.name}';

    final cached = _adaptiveSchemeCache.remove(cacheKey);
    if (cached != null) {
      _adaptiveSchemeCache[cacheKey] = cached;
      return applyAdaptivePlayerTint(
        baseScheme,
        cached,
        surfaceStyle: _surfaceStyle,
      );
    }

    final existing = _inFlightAdaptiveRequests[cacheKey];
    if (existing != null) {
      final resolved = await existing;
      if (resolved == null) return null;
      return applyAdaptivePlayerTint(
        baseScheme,
        resolved,
        surfaceStyle: _surfaceStyle,
      );
    }

    final Future<ColorScheme?> future = () async {
      try {
        final provider = CachedNetworkImageProvider(normalizedUrl);
        final scheme = await _adaptiveSchemeLoader(
          provider,
          baseScheme.brightness,
        ).timeout(const Duration(seconds: 6));

        if (_adaptiveSchemeCache.length >= maxAdaptiveCacheEntries) {
          _adaptiveSchemeCache.remove(_adaptiveSchemeCache.keys.first);
        }
        _adaptiveSchemeCache[cacheKey] = scheme;
        return scheme;
      } catch (_) {
        return null;
      } finally {
        _inFlightAdaptiveRequests.remove(cacheKey);
      }
    }();

    _inFlightAdaptiveRequests[cacheKey] = future;
    final resolved = await future;
    if (resolved == null) return null;
    return applyAdaptivePlayerTint(
      baseScheme,
      resolved,
      surfaceStyle: _surfaceStyle,
    );
  }

  /// Blends [artworkScheme]'s surface mood into [base] while preserving surface style
  /// character and accessible foreground contrast.
  static ColorScheme applyAdaptivePlayerTint(
    ColorScheme base,
    ColorScheme artworkScheme, {
    ThemeSurfaceStyle surfaceStyle = ThemeSurfaceStyle.oledBlack,
  }) {
    final isDark = base.brightness == Brightness.dark;
    final tintTarget = isDark
        ? Color.lerp(
            artworkScheme.surfaceContainerLow,
            artworkScheme.primaryContainer,
            0.42,
          )!
        : Color.lerp(
            artworkScheme.surface,
            artworkScheme.primaryContainer,
            0.34,
          )!;

    final double surfaceStrength;
    final double containerStrength;
    switch (surfaceStyle) {
      case ThemeSurfaceStyle.oledBlack:
        surfaceStrength = isDark ? 0.22 : 0.14;
        containerStrength = isDark ? 0.28 : 0.18;
        break;
      case ThemeSurfaceStyle.materialNeutral:
        surfaceStrength = isDark ? 0.28 : 0.18;
        containerStrength = isDark ? 0.34 : 0.22;
        break;
      case ThemeSurfaceStyle.tinted:
        surfaceStrength = isDark ? 0.40 : 0.28;
        containerStrength = isDark ? 0.45 : 0.32;
        break;
      case ThemeSurfaceStyle.highContrast:
        surfaceStrength = isDark ? 0.12 : 0.08;
        containerStrength = isDark ? 0.18 : 0.12;
        break;
    }

    final tintedSurface = Color.lerp(base.surface, tintTarget, surfaceStrength)!;
    final tintedLowest = Color.lerp(
      base.surfaceContainerLowest,
      tintTarget,
      surfaceStrength * 0.8,
    )!;
    final tintedLow = Color.lerp(
      base.surfaceContainerLow,
      tintTarget,
      containerStrength,
    )!;
    final tintedContainer = Color.lerp(
      base.surfaceContainer,
      tintTarget,
      containerStrength,
    )!;
    final tintedHigh = Color.lerp(
      base.surfaceContainerHigh,
      artworkScheme.primaryContainer,
      containerStrength * 0.85,
    )!;
    final tintedHighest = Color.lerp(
      base.surfaceContainerHighest,
      artworkScheme.primaryContainer,
      containerStrength * 0.78,
    )!;

    return base.copyWith(
      surface: tintedSurface,
      surfaceContainerLowest: tintedLowest,
      surfaceContainerLow: tintedLow,
      surfaceContainer: tintedContainer,
      surfaceContainerHigh: tintedHigh,
      surfaceContainerHighest: tintedHighest,
      outlineVariant: Color.lerp(
        base.outlineVariant,
        artworkScheme.primary,
        0.18,
      )!,
    );
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

  /// Picks whichever of white or black yields higher WCAG contrast on [background].
  static Color bestContrastInk(Color background) {
    return contrastRatio(background, Colors.white) >=
            contrastRatio(background, Colors.black)
        ? Colors.white
        : Colors.black;
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

  /// Builds a contrast-verified Material 3 [ColorScheme] for [seed], [brightness],
  /// and [surfaceStyle] (defaulting to [pureBlack] for legacy callers).
  static ColorScheme buildColorScheme({
    required Color seed,
    required Brightness brightness,
    bool pureBlack = true,
    ThemeSurfaceStyle? surfaceStyle,
  }) {
    final style = surfaceStyle ??
        (pureBlack
            ? ThemeSurfaceStyle.oledBlack
            : ThemeSurfaceStyle.materialNeutral);
    final isHighContrast = style == ThemeSurfaceStyle.highContrast;
    final double minPrimaryContrast = isHighContrast ? 8.5 : 7.0;

    if (isMonochromeSeed(seed)) {
      final baseMono = ColorScheme.fromSeed(
        seedColor: const Color(0xFF52525B),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      );
      final monoAccentScheme = _buildMonochromeAccentRoles(
        baseMono,
        brightness: brightness,
        isHighContrast: isHighContrast,
      );
      return _applySurfaceTokens(
        monoAccentScheme,
        seed: seed,
        brightness: brightness,
        style: style,
      );
    }

    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    final ColorScheme accentTuned;
    if (brightness == Brightness.light) {
      if (argb32(seed) == 0xFF8E24AA && !isHighContrast) {
        accentTuned = base.copyWith(
          primary: const Color(0xFF6E1B6E),
          onPrimary: const Color(0xFFFFFFFF),
          primaryContainer: const Color(0xFFEEDBF3),
          onPrimaryContainer: const Color(0xFF491454),
        );
      } else {
        accentTuned = _tuneLightContrast(
          base,
          minContrast: minPrimaryContrast,
        );
      }
    } else {
      if (argb32(seed) == 0xFF8E24AA && !isHighContrast) {
        accentTuned = base.copyWith(
          primary: const Color(0xFFCE82E3),
          onPrimary: const Color(0xFF16071B),
          primaryContainer: const Color(0xFF3A1C44),
          onPrimaryContainer: const Color(0xFFF0CCF8),
        );
      } else if (argb32(seed) == 0xFF1E88E5 && !isHighContrast) {
        accentTuned = base.copyWith(
          primary: const Color(0xFF4EA1FF),
          onPrimary: const Color(0xFF041122),
          primaryContainer: const Color(0xFF132E4D),
          onPrimaryContainer: const Color(0xFFD3E6FF),
        );
      } else {
        accentTuned = _tuneDarkContrast(
          base,
          minContrast: minPrimaryContrast,
        );
      }
    }

    return _applySurfaceTokens(
      accentTuned,
      seed: seed,
      brightness: brightness,
      style: style,
    );
  }

  static ColorScheme _buildMonochromeAccentRoles(
    ColorScheme base, {
    required Brightness brightness,
    required bool isHighContrast,
  }) {
    if (brightness == Brightness.dark) {
      return base.copyWith(
        primary: const Color(0xFFFFFFFF),
        onPrimary: const Color(0xFF000000),
        primaryContainer:
            isHighContrast ? const Color(0xFF303038) : const Color(0xFF28282E),
        onPrimaryContainer: const Color(0xFFFFFFFF),
        secondary: const Color(0xFFDADAE2),
        onSecondary: const Color(0xFF0A0A0D),
        secondaryContainer: const Color(0xFF23232A),
        onSecondaryContainer: const Color(0xFFF4F4F8),
        tertiary: const Color(0xFFB8B8C4),
        onTertiary: const Color(0xFF0A0A0D),
        tertiaryContainer: const Color(0xFF26262E),
        onTertiaryContainer: const Color(0xFFECECF2),
      );
    }

    return base.copyWith(
      primary:
          isHighContrast ? const Color(0xFF000000) : const Color(0xFF121216),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer:
          isHighContrast ? const Color(0xFFD8D8E2) : const Color(0xFFE6E6EC),
      onPrimaryContainer: const Color(0xFF09090C),
      secondary: const Color(0xFF36363E),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFEBEBF0),
      onSecondaryContainer: const Color(0xFF16161B),
      tertiary: const Color(0xFF52525E),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFFE0E0E8),
      onTertiaryContainer: const Color(0xFF16161B),
    );
  }

  static Color _hsl(double h, double s, double l) {
    return HSLColor.fromAHSL(
      1.0,
      h % 360.0,
      s.clamp(0.0, 1.0),
      l.clamp(0.0, 1.0),
    ).toColor();
  }

  static ColorScheme _applySurfaceTokens(
    ColorScheme scheme, {
    required Color seed,
    required Brightness brightness,
    required ThemeSurfaceStyle style,
  }) {
    final isMono = isMonochromeSeed(seed);
    final seedHsl = HSLColor.fromColor(seed);
    final hue = isMono ? 0.0 : seedHsl.hue;
    final sat = isMono ? 0.0 : seedHsl.saturation;

    if (brightness == Brightness.light) {
      switch (style) {
        case ThemeSurfaceStyle.oledBlack:
          return scheme.copyWith(
            surface: const Color(0xFFFFFFFF),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow:
                isMono ? const Color(0xFFF5F5F7) : const Color(0xFFF6F6FA),
            surfaceContainer:
                isMono ? const Color(0xFFEFEFF2) : const Color(0xFFEFEFF5),
            surfaceContainerHigh:
                isMono ? const Color(0xFFE7E7EB) : const Color(0xFFE8E8F0),
            surfaceContainerHighest:
                isMono ? const Color(0xFFDFDFE5) : const Color(0xFFDFDFE8),
            onSurface: const Color(0xFF121216),
            onSurfaceVariant: const Color(0xFF52525E),
            outline: const Color(0xFF747482),
            outlineVariant: const Color(0xFFDCDCE5),
          );
        case ThemeSurfaceStyle.materialNeutral:
          return scheme.copyWith(
            surface: const Color(0xFFF7F7F9),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFFFFFFF),
            surfaceContainer: const Color(0xFFEFEFF3),
            surfaceContainerHigh: const Color(0xFFE7E7EC),
            surfaceContainerHighest: const Color(0xFFDFDFE6),
            onSurface: const Color(0xFF16161A),
            onSurfaceVariant: const Color(0xFF55555F),
            outline: const Color(0xFF767682),
            outlineVariant: const Color(0xFFD5D5DF),
          );
        case ThemeSurfaceStyle.tinted:
          final lSat = isMono ? 0.0 : sat.clamp(0.18, 0.42);
          return scheme.copyWith(
            surface: _hsl(hue, lSat * 0.85, 0.955),
            surfaceContainerLowest: _hsl(hue, lSat * 0.45, 0.992),
            surfaceContainerLow: _hsl(hue, lSat * 0.50, 0.985),
            surfaceContainer: _hsl(hue, lSat * 0.78, 0.925),
            surfaceContainerHigh: _hsl(hue, lSat * 0.78, 0.895),
            surfaceContainerHighest: _hsl(hue, lSat * 0.76, 0.860),
            onSurface: _hsl(hue, math.min(0.28, lSat * 0.55), 0.10),
            onSurfaceVariant: _hsl(hue, math.min(0.24, lSat * 0.48), 0.34),
            outline: _hsl(hue, math.min(0.22, lSat * 0.45), 0.48),
            outlineVariant: _hsl(hue, math.min(0.26, lSat * 0.52), 0.80),
          );
        case ThemeSurfaceStyle.highContrast:
          return scheme.copyWith(
            surface: const Color(0xFFFFFFFF),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFF2F2F7),
            surfaceContainer: const Color(0xFFE6E6EE),
            surfaceContainerHigh: const Color(0xFFDCDCE6),
            surfaceContainerHighest: const Color(0xFFCFCFD9),
            onSurface: const Color(0xFF000000),
            onSurfaceVariant: const Color(0xFF262630),
            outline: const Color(0xFF484856),
            outlineVariant: const Color(0xFF8A8A9D),
          );
      }
    }

    switch (style) {
      case ThemeSurfaceStyle.oledBlack:
        return scheme.copyWith(
          surface: const Color(0xFF000000),
          surfaceContainerLowest: const Color(0xFF000000),
          surfaceContainerLow:
              isMono ? const Color(0xFF121214) : const Color(0xFF131318),
          surfaceContainer:
              isMono ? const Color(0xFF17171A) : const Color(0xFF17171E),
          surfaceContainerHigh:
              isMono ? const Color(0xFF1D1D21) : const Color(0xFF1C1C22),
          surfaceContainerHighest:
              isMono ? const Color(0xFF242429) : const Color(0xFF22222A),
          onSurface: isMono ? const Color(0xFFFFFFFF) : const Color(0xFFF5F4F8),
          onSurfaceVariant:
              isMono ? const Color(0xFFB4B4BC) : const Color(0xFFA8A8B4),
          outline: const Color(0xFF767682),
          outlineVariant:
              isMono ? const Color(0xFF2C2C33) : const Color(0xFF2B2B35),
        );
      case ThemeSurfaceStyle.materialNeutral:
        return scheme.copyWith(
          surface: const Color(0xFF121212),
          surfaceContainerLowest: const Color(0xFF0B0B0D),
          surfaceContainerLow: const Color(0xFF1B1B1E),
          surfaceContainer: const Color(0xFF212125),
          surfaceContainerHigh: const Color(0xFF28282E),
          surfaceContainerHighest: const Color(0xFF323238),
          onSurface: const Color(0xFFF2F2F5),
          onSurfaceVariant: const Color(0xFFB2B2BC),
          outline: const Color(0xFF7E7E8A),
          outlineVariant: const Color(0xFF383842),
        );
      case ThemeSurfaceStyle.tinted:
        final tSat = isMono ? 0.0 : sat.clamp(0.22, 0.52);
        return scheme.copyWith(
          surface: _hsl(hue, tSat, 0.055),
          surfaceContainerLowest: _hsl(hue, tSat, 0.035),
          surfaceContainerLow: _hsl(hue, tSat * 0.94, 0.095),
          surfaceContainer: _hsl(hue, tSat * 0.88, 0.125),
          surfaceContainerHigh: _hsl(hue, tSat * 0.82, 0.160),
          surfaceContainerHighest: _hsl(hue, tSat * 0.76, 0.205),
          onSurface: _hsl(hue, math.min(0.20, tSat * 0.35), 0.95),
          onSurfaceVariant: _hsl(hue, math.min(0.22, tSat * 0.35), 0.74),
          outline: _hsl(hue, math.min(0.24, tSat * 0.35), 0.52),
          outlineVariant: _hsl(hue, math.min(0.30, tSat * 0.45), 0.26),
        );
      case ThemeSurfaceStyle.highContrast:
        return scheme.copyWith(
          surface: const Color(0xFF000000),
          surfaceContainerLowest: const Color(0xFF000000),
          surfaceContainerLow: const Color(0xFF101014),
          surfaceContainer: const Color(0xFF18181E),
          surfaceContainerHigh: const Color(0xFF22222A),
          surfaceContainerHighest: const Color(0xFF2D2D37),
          onSurface: const Color(0xFFFFFFFF),
          onSurfaceVariant: const Color(0xFFD8D8E4),
          outline: const Color(0xFFA0A0B0),
          outlineVariant: const Color(0xFF565668),
        );
    }
  }

  static ColorScheme _tuneDarkContrast(
    ColorScheme scheme, {
    double minContrast = 7.0,
  }) {
    var primary = scheme.primary;
    final hsl = HSLColor.fromColor(primary);

    final targetFloorLightness = minContrast >= 8.0 ? 0.72 : 0.68;
    if (hsl.lightness < targetFloorLightness) {
      primary = hsl
          .withLightness(targetFloorLightness)
          .withSaturation(math.min(0.88, hsl.saturation))
          .toColor();
    }

    final darkInk = minContrast >= 8.0
        ? const Color(0xFF000000)
        : HSLColor.fromColor(primary).withLightness(0.08).toColor();

    var l = HSLColor.fromColor(primary).lightness;
    while (l < 0.88 && contrastRatio(primary, darkInk) < minContrast) {
      l += 0.02;
      primary = HSLColor.fromColor(primary).withLightness(l).toColor();
    }
    final onPrimary = contrastRatio(primary, darkInk) >= minContrast
        ? darkInk
        : const Color(0xFF000000);

    var container = scheme.primaryContainer;
    var onContainer = scheme.onPrimaryContainer;
    if (contrastRatio(onContainer, container) < minContrast) {
      onContainer = HSLColor.fromColor(container).withLightness(0.92).toColor();
      if (contrastRatio(onContainer, container) < minContrast) {
        container = HSLColor.fromColor(container).withLightness(0.18).toColor();
      }
      if (contrastRatio(onContainer, container) < minContrast) {
        onContainer = const Color(0xFFFFFFFF);
      }
    }

    return scheme.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
    );
  }

  static ColorScheme _tuneLightContrast(
    ColorScheme scheme, {
    double minContrast = 7.0,
  }) {
    var primary = scheme.primary;
    const lightOnPrimary = Color(0xFFFFFFFF);
    final hsl = HSLColor.fromColor(primary);

    if (contrastRatio(primary, lightOnPrimary) < minContrast) {
      var l = hsl.lightness;
      while (l > 0.12 && contrastRatio(primary, lightOnPrimary) < minContrast) {
        l -= 0.02;
        primary = hsl.withLightness(l).toColor();
      }
    }

    var container = scheme.primaryContainer;
    var onContainer = scheme.onPrimaryContainer;
    if (contrastRatio(onContainer, container) < minContrast) {
      onContainer = HSLColor.fromColor(primary).withLightness(0.14).toColor();
      if (contrastRatio(onContainer, container) < minContrast) {
        container =
            HSLColor.fromColor(container).withLightness(0.90).toColor();
      }
      if (contrastRatio(onContainer, container) < minContrast) {
        onContainer = const Color(0xFF000000);
      }
    }

    return scheme.copyWith(
      primary: primary,
      onPrimary: lightOnPrimary,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
    );
  }

  /// Builds a full Material 3 [ThemeData] for [colorScheme].
  static ThemeData buildThemeData(
    ColorScheme colorScheme, {
    ThemeSurfaceStyle surfaceStyle = ThemeSurfaceStyle.oledBlack,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final isHighContrast = surfaceStyle == ThemeSurfaceStyle.highContrast;

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isHighContrast
              ? BorderSide(color: colorScheme.outlineVariant, width: 1.0)
              : BorderSide.none,
        ),
        color: colorScheme.surfaceContainerLow,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(
          alpha: isHighContrast ? 0.72 : (isDark ? 0.28 : 0.45),
        ),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: isHighContrast
              ? BorderSide(color: colorScheme.outlineVariant, width: 1.0)
              : BorderSide.none,
        ),
        side: isHighContrast
            ? BorderSide(color: colorScheme.outlineVariant, width: 1.0)
            : BorderSide.none,
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
        trackOutlineColor: WidgetStateProperty.all(
          isHighContrast ? colorScheme.outlineVariant : Colors.transparent,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
    );
  }

  ThemeData themeForBrightness(Brightness brightness) {
    return buildThemeData(
      buildColorScheme(
        seed: _accentColor,
        brightness: brightness,
        surfaceStyle: _surfaceStyle,
      ),
      surfaceStyle: _surfaceStyle,
    );
  }

  ThemeData get lightTheme => themeForBrightness(Brightness.light);

  ThemeData get darkTheme => themeForBrightness(Brightness.dark);
}
