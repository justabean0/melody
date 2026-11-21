import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/build_flags.dart';
import 'providers/playback_provider.dart';
import 'providers/library_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/search_provider.dart';
import 'services/audio_cache_service.dart';
import 'services/database_service.dart';
import 'services/log_service.dart';
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

class _MainScaffoldState extends State<MainScaffold> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      DatabaseService.getBackgroundPlaybackEnabled().then((bgEnabled) {
        if (!bgEnabled && mounted) {
          final playback = context.read<PlaybackProvider>();
          if (playback.isPlaying) {
            playback.togglePlayPause();
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Stack(
        children: [
          RepaintBoundary(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
              child: MiniPlayer(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        animationDuration: const Duration(milliseconds: 180),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (_currentIndex == index) return;
          const tabNames = ['Home', 'Search', 'Library', 'Settings'];
          final fromTab = _currentIndex < tabNames.length ? tabNames[_currentIndex] : 'Tab $_currentIndex';
          final toTab = index < tabNames.length ? tabNames[index] : 'Tab $index';
          LogService.recordBreadcrumb(
            'Tab switched from $fromTab to $toTab',
            category: 'navigation',
          );
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
