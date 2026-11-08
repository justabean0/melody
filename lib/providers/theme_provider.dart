import 'package:flutter/material.dart';
import '../services/database_service.dart';

class ThemeProvider extends ChangeNotifier {
  late ThemeMode _themeMode;
  late bool _pureBlack;
  late Color _accentColor;

  ThemeMode get themeMode => _themeMode;
  bool get pureBlack => _pureBlack;
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

    _pureBlack = DatabaseService.getPureBlack();
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

  void setPureBlack(bool val) {
    _pureBlack = val;
    DatabaseService.setPureBlack(val);
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    // ignore: deprecated_member_use
    DatabaseService.setAccentColor(color.value);
    notifyListeners();
  }

  ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: colorScheme.surfaceContainerHighest.withAlpha(128),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
      ),
    );
  }

  ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.dark,
    );

    final bg = _pureBlack ? Colors.black : colorScheme.surface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: _pureBlack
            ? const Color(0xFF141414)
            : colorScheme.surfaceContainerHighest.withAlpha(128),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        indicatorColor: colorScheme.primaryContainer,
      ),
    );
  }
}
