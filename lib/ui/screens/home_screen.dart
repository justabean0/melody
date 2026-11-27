import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/browse_result.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../services/database_service.dart';
import '../../services/innertube_service.dart';
import '../../services/recommendation_service.dart';
import '../../services/stream_resolver_service.dart';
import '../../services/update_service.dart';
import '../../widgets/skeleton_loaders.dart';
import '../components/album_card.dart';
import '../components/language_selection_dialog.dart';
import '../components/song_tile.dart';
import '../components/update_dialog.dart';
import 'collection_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _quickPicks = [];
  List<BrowseMediaItem> _browseItems = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _feedRequestToken = 0;
  Timer? _preWarmTimer;
  String _activeMood = 'All';
  List<String> _lastLoadedLanguages = [];

  final List<String> _moods = [
    'All',
    'Chill',
    'Workout',
    'Focus',
    'Party',
    'Romance',
    'Sleep',
  ];

  @override
  void initState() {
    super.initState();
    _lastLoadedLanguages = DatabaseService.getMusicLanguages();
    DatabaseService.musicLanguagesNotifier.addListener(_onLanguagesChanged);
    _checkAppUpdateSilently();
    _initializeHome();
  }

  @override
  void dispose() {
    DatabaseService.musicLanguagesNotifier.removeListener(_onLanguagesChanged);
    _preWarmTimer?.cancel();
    super.dispose();
  }

  void _onLanguagesChanged() {
    final current = DatabaseService.getMusicLanguages();
    if (!listEquals(current, _lastLoadedLanguages)) {
      _lastLoadedLanguages = current;
      if (mounted) {
        setState(() => _isLoading = true);
        _loadFeed(_activeMood, true);
      }
    }
  }

  Future<void> _initializeHome() async {
    final hasLangs = DatabaseService.hasSelectedMusicLanguages();
    final onboardingDone = DatabaseService.hasCompletedLanguageOnboarding();

    if (!hasLangs && !onboardingDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final tokenBefore = _feedRequestToken;
        await _checkFirstTimeLanguageSetup();
        if (mounted && _feedRequestToken == tokenBefore) {
          await _loadFeed('All', false);
        }
      });
    } else {
      _loadFeed('All', false);
    }
  }

  Future<void> _checkFirstTimeLanguageSetup() async {
    if (!DatabaseService.hasCompletedLanguageOnboarding()) {
      await LanguageSelectionDialog.show(
        context,
        isDismissible: false,
        onSaved: (selected) {},
      );
      if (!DatabaseService.hasCompletedLanguageOnboarding()) {
        await DatabaseService.markLanguageOnboardingCompleted();
      }
    }
  }

  Future<void> _checkAppUpdateSilently() async {
    if (!DatabaseService.getAutoCheckUpdates()) return;

    final lastCheck = DatabaseService.getLastUpdateCheck();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCheck < const Duration(hours: 6).inMilliseconds) return;

    await DatabaseService.setLastUpdateCheck(now);

    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final info = await UpdateService.checkForUpdate();
    if (info != null && info.hasUpdate && mounted) {
      UpdateDialog.show(context, info);
    }
  }

  Future<void> _loadFeed([String mood = 'All', bool isUserRefresh = false]) async {
    final requestToken = ++_feedRequestToken;

    final activeLangs = DatabaseService.getMusicLanguages();
    _lastLoadedLanguages = activeLangs;
    final cacheKey = '$mood:${activeLangs.join(",")}';

    // 1. Instant display from cache (0ms perceived latency)
    final cached = InnerTubeService.sanitizeSongs(
      DatabaseService.getCachedFeed(cacheKey),
    );
    if (cached.isNotEmpty && !isUserRefresh) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _quickPicks = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
    } else if (_quickPicks.isEmpty || isUserRefresh) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }
    }

    // 2. Fetch fresh personalized feed + featured browse items concurrently
    try {
      final results = await Future.wait([
        InnerTubeService.getQuickPicks(
          languages: activeLangs,
          mood: mood,
          forceRefresh: isUserRefresh || cached.isEmpty,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('Feed network request timed out - falling back to cache');
            return cached;
          },
        ),
        RecommendationService.getFeaturedBrowseItems(
          languages: activeLangs,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () => <BrowseMediaItem>[],
        ),
      ]);

      if (!mounted || requestToken != _feedRequestToken) return;

      final songs = results[0] as List<Song>;
      final browse = results[1] as List<BrowseMediaItem>;

      setState(() {
        if (songs.isNotEmpty) {
          _quickPicks = songs;
          _hasError = false;
        } else if (_quickPicks.isEmpty && cached.isEmpty) {
          _hasError = true;
        }
        if (browse.isNotEmpty) {
          _browseItems = browse;
        }
        _isLoading = false;
      });

      if (songs.isNotEmpty) {
        _preWarmTimer?.cancel();
        _preWarmTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted || requestToken != _feedRequestToken) return;
          for (final s in songs.take(2)) {
            StreamResolverService.preWarm(s.id, songTitle: s.title, artist: s.artist);
          }
        });
      }
    } catch (_) {
      if (!mounted || requestToken != _feedRequestToken) return;
      setState(() {
        if (_quickPicks.isEmpty && cached.isEmpty) {
          _hasError = true;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;

    final albumItems = _browseItems.where((b) => b.type == 'album').toList();
    final featuredNonAlbums =
        _browseItems.where((b) => b.type != 'album').toList();
    final featuredItems =
        featuredNonAlbums.isNotEmpty ? featuredNonAlbums : _browseItems;

    final int quickPickLimit = _quickPicks.length >= 16
        ? ((_quickPicks.length ~/ 4) * 4).clamp(16, 20)
        : _quickPicks.length;
    final quickPickPool = _quickPicks.take(quickPickLimit).toList();
    final int quickPickColumns =
        quickPickPool.isEmpty ? 0 : ((quickPickPool.length - 1) ~/ 4) + 1;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildBrandHeader(theme, colorScheme),
            _buildMoodChips(colorScheme),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_isLoading) return;
                  await _loadFeed(_activeMood, true);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isLoading
                      ? const HomeFeedSkeleton(
                          key: ValueKey('home_skeleton'),
                          showMoodChips: false,
                        )
                      : _hasError && _quickPicks.isEmpty
                          ? _buildErrorState(theme, colorScheme, bottomPadding)
                          : ListView(
                              key: const ValueKey('home_content'),
                              padding: EdgeInsets.only(bottom: bottomPadding),
                              children: [
                                const SizedBox(height: 18),
                                _buildQuickPicksHeader(theme, colorScheme, playback),
                                const SizedBox(height: 6),
                                if (quickPickColumns > 0)
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final colWidth =
                                          (constraints.maxWidth * 0.91)
                                              .clamp(280.0, 420.0);
                                      return SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        padding:
                                            const EdgeInsets.only(right: 14),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: List.generate(
                                            quickPickColumns,
                                            (colIndex) {
                                              final start = colIndex * 4;
                                              final end = (start + 4).clamp(
                                                  0, quickPickPool.length);
                                              final colSongs = quickPickPool
                                                  .sublist(start, end);
                                              return SizedBox(
                                                width: colWidth,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: colSongs
                                                      .map(
                                                        (song) => SongTile(
                                                          song: song,
                                                          contextQueue:
                                                              _quickPicks,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .fromLTRB(
                                                                  16, 0, 2, 0),
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                if (featuredItems.isNotEmpty) ...[
                                  const SizedBox(height: 22),
                                  _buildSectionTitle(
                                    'Featured & Trending',
                                    theme,
                                    colorScheme,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildBrowseShelf(featuredItems),
                                ],
                                if (albumItems.isNotEmpty &&
                                    featuredNonAlbums.isNotEmpty) ...[
                                  const SizedBox(height: 22),
                                  _buildSectionTitle(
                                    'Albums',
                                    theme,
                                    colorScheme,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildBrowseShelf(albumItems),
                                ],
                                if (_quickPicks.length > quickPickPool.length) ...[
                                  const SizedBox(height: 22),
                                  _buildSectionTitle(
                                    'More For You',
                                    theme,
                                    colorScheme,
                                  ),
                                  const SizedBox(height: 8),
                                  ..._quickPicks.skip(quickPickPool.length).map(
                                        (song) => SongTile(
                                          song: song,
                                          contextQueue: _quickPicks,
                                        ),
                                      ),
                                ],
                              ],
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader(ThemeData theme, ColorScheme colorScheme) {
    final isLight = colorScheme.brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isLight
                    ? colorScheme.outlineVariant.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/images/logo.png',
                width: 27,
                height: 27,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.music_note_rounded,
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Melody',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.05,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Music Languages',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              Icons.translate_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              final tokenBefore = _feedRequestToken;
              LanguageSelectionDialog.show(
                context,
                isDismissible: true,
                onSaved: (_) {
                  if (_feedRequestToken == tokenBefore) {
                    setState(() => _isLoading = true);
                    _loadFeed(_activeMood, true);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChips(ColorScheme colorScheme) {
    final textScaler = MediaQuery.textScalerOf(context);
    final chipStripHeight = math.max(48.0, 28.0 + textScaler.scale(20.0));

    return SizedBox(
      height: chipStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _moods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mood = _moods[index];
          final isSelected = _activeMood == mood;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilterChip(
                label: Text(
                  mood,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                ),
                selected: isSelected,
                showCheckmark: false,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                backgroundColor: colorScheme.surfaceContainerHigh,
                selectedColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  setState(() {
                    _activeMood = mood;
                    _isLoading = true;
                  });
                  _loadFeed(mood, false);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickPicksHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    PlaybackProvider playback,
  ) {
    final hasSongs = _quickPicks.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Quick Picks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            enabled: hasSongs,
            label: 'Play all quick picks',
            child: Opacity(
              opacity: hasSongs ? 1.0 : 0.45,
              child: InkWell(
                onTap: hasSongs
                    ? () => playback.playSong(_quickPicks.first,
                        contextQueue: _quickPicks)
                    : null,
                borderRadius: BorderRadius.circular(999),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Play all',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildBrowseShelf(List<BrowseMediaItem> items) {
    final shelfHeight =
        138.0 + 14.0 + MediaQuery.textScalerOf(context).scale(44.0);
    return SizedBox(
      height: shelfHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16.0, right: 4.0),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return MediaCard(
            size: 138,
            title: item.title,
            subtitle: item.subtitle,
            imageUrl: item.thumbnailUrl,
            onTap: () {
              final browseId = item.browseId ?? item.id;
              if (browseId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CollectionDetailScreen(
                    browseId: browseId,
                    isAlbum: item.type == 'album',
                    title: item.title,
                    subtitle: item.subtitle,
                    thumbnailUrl: item.thumbnailUrl,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorState(
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    return Center(
      key: const ValueKey('home_error'),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, bottomPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Unable to load music feed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _loadFeed(_activeMood, true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
