import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/build_flags.dart';
import 'providers/playback_provider.dart';
import 'providers/library_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/search_provider.dart';
import 'services/audio_cache_service.dart';
import 'services/audio_service.dart';
import 'services/database_service.dart';
import 'services/download_service.dart';
import 'services/log_service.dart';
import 'services/stream_resolver_service.dart';
import 'ui/components/mini_player.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/search_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.init();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kIsDiagnosticsEnabled) {
      LogService.recordBreadcrumb(
        'Flutter error: ${details.summary}',
        category: 'error',
      );
      LogService.error(
        details.summary.toString(),
        tag: 'FlutterError',
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
      );
    }
  };

  PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
    if (kIsDiagnosticsEnabled) {
      LogService.recordBreadcrumb(
        'Platform async error: $err',
        category: 'error',
      );
      LogService.error(
        'Uncaught async error: $err',
        tag: 'PlatformError',
        error: err.toString(),
        stackTrace: stack.toString(),
      );
    }
    return false;
  };

  await DatabaseService.init();
  await AudioCacheService.init();
  DownloadService().restorePersistedDownloads();
  unawaited(DownloadService().reconcileWithMediaStore());
  unawaited(StreamResolverService.initInstances());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => PlaybackProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: const MelodyApp(),
    ),
  );
}

/// Returns the edge-to-edge [SystemUiOverlayStyle] tuned for [brightness].
SystemUiOverlayStyle systemUiOverlayStyleForBrightness(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}

class _SystemUiOverlaySync extends StatefulWidget {
  final Widget child;

  const _SystemUiOverlaySync({required this.child});

  @override
  State<_SystemUiOverlaySync> createState() => _SystemUiOverlaySyncState();
}

class _SystemUiOverlaySyncState extends State<_SystemUiOverlaySync>
    with WidgetsBindingObserver {
  Brightness? _lastAppliedBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      MelodyAudioService.flushActiveListeningStats();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(DownloadService().reconcileWithMediaStore());
    }
  }

  void _syncOverlay(Brightness brightness) {
    if (_lastAppliedBrightness == brightness) return;
    _lastAppliedBrightness = brightness;
    final style = systemUiOverlayStyleForBrightness(brightness);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChrome.setSystemUIOverlayStyle(style);
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final style = systemUiOverlayStyleForBrightness(brightness);
    _syncOverlay(brightness);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: widget.child,
    );
  }
}

class MelodyApp extends StatelessWidget {
  const MelodyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Melody',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return _SystemUiOverlaySync(child: child);
      },
      home: const MainScaffold(),
      navigatorObservers: [
        DiagnosticNavigatorObserver(),
      ],
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  void _onSelectTab(int index) {
    if (_currentIndex == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    const tabNames = ['Home', 'Search', 'Library', 'Settings'];
    final fromTab =
        _currentIndex < tabNames.length ? tabNames[_currentIndex] : 'Tab $_currentIndex';
    final toTab = index < tabNames.length ? tabNames[index] : 'Tab $index';
    LogService.recordBreadcrumb(
      'Tab switched from $fromTab to $toTab',
      category: 'navigation',
    );
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return _SystemUiOverlaySync(
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            RepaintBoundary(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FloatingBottomDock(
                selectedIndex: _currentIndex,
                onSelectTab: _onSelectTab,
                showNavBar: !isKeyboardOpen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBottomDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final bool showNavBar;

  const _FloatingBottomDock({
    required this.selectedIndex,
    required this.onSelectTab,
    this.showNavBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasSong = context.select<PlaybackProvider, bool>(
      (p) => p.currentSong != null,
    );
    if (!hasSong && !showNavBar) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    const double topFeatherHeight = 18.0;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.34, 0.68, 1.0],
                  colors: [
                    colorScheme.surface.withValues(alpha: 0.0),
                    colorScheme.surface.withValues(alpha: 0.68),
                    colorScheme.surface.withValues(alpha: 0.94),
                    colorScheme.surface.withValues(alpha: 0.98),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: topFeatherHeight),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('floating_dock_hit_barrier'),
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onDoubleTap: () {},
                  onLongPress: () {},
                  child: const SizedBox.expand(),
                ),
              ),
              SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    0,
                    14,
                    showNavBar ? 10 : 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSong) const RepaintBoundary(child: MiniPlayer()),
                      if (hasSong && showNavBar) const SizedBox(height: 10),
                      if (showNavBar)
                        _FloatingNavBar(
                          selectedIndex: selectedIndex,
                          onSelectTab: onSelectTab,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: isDark
            ? null
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                width: 1,
              ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.52)
                : colorScheme.shadow.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _FloatingNavDestination(
            label: 'Home',
            selected: selectedIndex == 0,
            onTap: () => onSelectTab(0),
            iconBuilder: (color, active) => Icon(
              active ? Icons.home_rounded : Icons.home_outlined,
              size: 24,
              color: color,
            ),
          ),
          _FloatingNavDestination(
            label: 'Search',
            selected: selectedIndex == 1,
            onTap: () => onSelectTab(1),
            iconBuilder: (color, active) => _SearchNavIcon(
              color: color,
              isActive: active,
            ),
          ),
          _FloatingNavDestination(
            label: 'Library',
            selected: selectedIndex == 2,
            onTap: () => onSelectTab(2),
            iconBuilder: (color, active) => _LibraryNavIcon(
              color: color,
              isActive: active,
            ),
          ),
          _FloatingNavDestination(
            label: 'Settings',
            selected: selectedIndex == 3,
            onTap: () => onSelectTab(3),
            iconBuilder: (color, active) => Icon(
              active ? Icons.settings : Icons.settings_outlined,
              size: 24,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavDestination extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget Function(Color color, bool active) iconBuilder;

  const _FloatingNavDestination({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.iconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeBg = colorScheme.primaryContainer;
    final activeFg = colorScheme.onPrimaryContainer;
    final inactiveFg = colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onTap,
            canRequestFocus: false,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 56,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: selected
                            ? Container(
                                key: ValueKey('nav_active_pill_$label'),
                                width: 56,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: activeBg,
                                  borderRadius: BorderRadius.circular(17),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      iconBuilder(
                        selected ? activeFg : inactiveFg,
                        selected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchNavIcon extends StatelessWidget {
  final Color color;
  final bool isActive;

  const _SearchNavIcon({required this.color, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _SearchIconPainter(color: color, isActive: isActive),
      ),
    );
  }
}

class _SearchIconPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  const _SearchIconPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 2.5 : 1.9
      ..strokeCap = StrokeCap.round;

    final scale = size.width / 24.0;
    canvas.drawCircle(
      Offset(10.5 * scale, 10.5 * scale),
      6.2 * scale,
      paint,
    );
    canvas.drawLine(
      Offset(15.1 * scale, 15.1 * scale),
      Offset(19.8 * scale, 19.8 * scale),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isActive != isActive;
}

class _LibraryNavIcon extends StatelessWidget {
  final Color color;
  final bool isActive;

  const _LibraryNavIcon({required this.color, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _LibraryIconPainter(color: color, isActive: isActive),
      ),
    );
  }
}

class _LibraryIconPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  const _LibraryIconPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 2.45 : 1.95
      ..strokeCap = StrokeCap.round;

    final scale = size.width / 24.0;
    const dx = -0.35;
    canvas.drawLine(
      Offset((6.5 + dx) * scale, 5.6 * scale),
      Offset((6.5 + dx) * scale, 18.4 * scale),
      paint,
    );
    canvas.drawLine(
      Offset((11.0 + dx) * scale, 5.6 * scale),
      Offset((11.0 + dx) * scale, 18.4 * scale),
      paint,
    );
    canvas.drawLine(
      Offset((15.0 + dx) * scale, 5.9 * scale),
      Offset((18.2 + dx) * scale, 18.1 * scale),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LibraryIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isActive != isActive;
}
