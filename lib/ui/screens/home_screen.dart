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
  final ScrollController _scrollController = ScrollController();
  List<Song> _quickPicks = [];
  List<BrowseMediaItem> _browseItems = [];
  List<BrowseMediaItem> _podcastShows = [];
  List<Song> _podcastEpisodes = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _feedRequestToken = 0;
  Timer? _preWarmTimer;
  String _activeMood = 'All';
  List<String> _lastLoadedLanguages = [];

  static const Duration _homeCacheTtl = Duration(minutes: 3);

  final List<String> _moods = [
    'All',
    'Podcasts',
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
    _restoreInitialHomeCacheSync();
    _checkAppUpdateSilently();
    _initializeHome();
  }

  @override
  void dispose() {
    DatabaseService.musicLanguagesNotifier.removeListener(_onLanguagesChanged);
    _preWarmTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _restoreInitialHomeCacheSync() {
    final hasLangs = DatabaseService.hasSelectedMusicLanguages();
    final onboardingDone = DatabaseService.hasCompletedLanguageOnboarding();
    if (!hasLangs && !onboardingDone) return;

    final activeLangs = DatabaseService.getMusicLanguages();
    final cacheKey = '$_activeMood:${activeLangs.join(",")}';
    final langKey = 'lang:${activeLangs.join(",")}';
    final cached = DatabaseService.getCachedHomeFeed(
      cacheKey,
      browseFallbackKey: langKey,
    );
    final sanitizedSongs = InnerTubeService.sanitizeSongs(cached.songs);
    if (sanitizedSongs.isNotEmpty) {
      _quickPicks = sanitizedSongs;
      _browseItems = cached.browseItems;
      _isLoading = false;
      _hasError = false;
    }
  }

  void _onLanguagesChanged() {
    final current = DatabaseService.getMusicLanguages();
    if (!listEquals(current, _lastLoadedLanguages)) {
      _lastLoadedLanguages = current;
      if (mounted) {
        setState(() {
          _isLoading = true;
          _browseItems = [];
          _podcastShows = [];
          _podcastEpisodes = [];
        });
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
          await _loadFeed(_activeMood, false);
        }
      });
    } else {
      await _loadFeed(_activeMood, false);
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
    if (mood == 'Podcasts') {
      await _loadPodcastsFeed(isUserRefresh);
      return;
    }

    final requestToken = ++_feedRequestToken;

    final activeLangs = DatabaseService.getMusicLanguages();
    _lastLoadedLanguages = activeLangs;
    final cacheKey = '$mood:${activeLangs.join(",")}';
    final browseFallbackKey = 'lang:${activeLangs.join(",")}';

    // 1. Atomic restoration from unified disk cache (Quick Picks + Featured & Trending + Albums)
    final cached = DatabaseService.getCachedHomeFeed(
      cacheKey,
      browseFallbackKey: browseFallbackKey,
    );
    final cachedSongs = InnerTubeService.sanitizeSongs(cached.songs);
    final cachedBrowse = cached.browseItems;
    final hasWarmCache = cachedSongs.isNotEmpty && !isUserRefresh;

    if (hasWarmCache) {
      if (mounted && requestToken == _feedRequestToken) {
        final needsInitialRestore =
            _isLoading || _quickPicks.isEmpty || _browseItems.isEmpty;
        if (needsInitialRestore) {
          setState(() {
            _quickPicks = cachedSongs;
            if (cachedBrowse.isNotEmpty) {
              _browseItems = cachedBrowse;
            }
            _isLoading = false;
            _hasError = false;
          });
        }
      }

      // Skip redundant network churn when disk cache is complete, within TTL,
      // and user hasn't played/liked new songs since it was written.
      final cachedTaste = DatabaseService.getCachedFeedTasteVersion(cacheKey);
      final tasteCurrent =
          cachedTaste == null || cachedTaste == DatabaseService.tasteVersion;
      final isFresh = cached.timestamp != null &&
          DateTime.now().difference(cached.timestamp!) < _homeCacheTtl;
      if (isFresh && tasteCurrent && cachedBrowse.isNotEmpty) {
        _schedulePreWarm(cachedSongs, requestToken);
        return;
      }
    } else if (_quickPicks.isEmpty || isUserRefresh) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }
    }

    // 2. Fetch Quick Picks + Featured & Albums concurrently via Future.wait
    final Song? activeSong =
        mounted ? context.read<PlaybackProvider>().currentSong : null;
    try {
      final results = await Future.wait([
        InnerTubeService.getQuickPicks(
          languages: activeLangs,
          mood: mood,
          forceRefresh: isUserRefresh || cachedSongs.isEmpty,
          activeSong: activeSong,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('Feed network request timed out - falling back to cache');
            return cachedSongs;
          },
        ),
        RecommendationService.getFeaturedBrowseItems(
          languages: activeLangs,
          forceRefresh: isUserRefresh || cachedBrowse.isEmpty,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () => cachedBrowse,
        ),
      ]);

      if (!mounted || requestToken != _feedRequestToken) return;

      final songs = results[0] as List<Song>;
      final browse = results[1] as List<BrowseMediaItem>;

      // Persist all Home sections together atomically to disk cache
      if (songs.isNotEmpty || browse.isNotEmpty) {
        unawaited(
          DatabaseService.saveCachedHomeFeed(
            cacheKey,
            songs: songs,
            browseItems: browse,
            browseFallbackKey: browseFallbackKey,
          ),
        );
      }

      // Avoid mid-scroll layout jumps if warm cache is already rendered and user scrolled down
      final userHasScrolled =
          !isUserRefresh &&
          !_isLoading &&
          _quickPicks.isNotEmpty &&
          _scrollController.hasClients &&
          _scrollController.offset > 24.0;

      if (!userHasScrolled) {
        setState(() {
          if (songs.isNotEmpty) {
            _quickPicks = songs;
            _hasError = false;
          } else if (_quickPicks.isEmpty && cachedSongs.isEmpty) {
            _hasError = true;
          }
          if (browse.isNotEmpty) {
            _browseItems = browse;
          }
          _isLoading = false;
        });
      }

      if (songs.isNotEmpty) {
        _schedulePreWarm(songs, requestToken);
      }
    } catch (_) {
      if (!mounted || requestToken != _feedRequestToken) return;
      setState(() {
        if (_quickPicks.isEmpty && cachedSongs.isEmpty) {
          _hasError = true;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPodcastsFeed(bool isUserRefresh) async {
    final requestToken = ++_feedRequestToken;
    final activeLangs = DatabaseService.getMusicLanguages();
    _lastLoadedLanguages = activeLangs;
    final langKey = activeLangs.join(',');

    final cached = DatabaseService.getCachedPodcasts(langKey);
    final hasCache =
        (cached.shows.isNotEmpty || cached.episodes.isNotEmpty) && !isUserRefresh;

    if (hasCache) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _podcastShows = cached.shows;
          _podcastEpisodes = cached.episodes;
          _isLoading = false;
          _hasError = false;
        });
      }
      final isFresh = cached.timestamp != null &&
          DateTime.now().difference(cached.timestamp!) < _homeCacheTtl;
      if (isFresh) return;
    } else if (mounted && requestToken == _feedRequestToken) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final result = await RecommendationService.getPodcastsFeed(
        languages: activeLangs,
        forceRefresh: isUserRefresh || !hasCache,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => (shows: cached.shows, episodes: cached.episodes),
      );

      if (!mounted || requestToken != _feedRequestToken) return;

      setState(() {
        if (result.shows.isNotEmpty || result.episodes.isNotEmpty) {
          _podcastShows = result.shows;
          _podcastEpisodes = result.episodes;
          _hasError = false;
        } else if (_podcastShows.isEmpty && _podcastEpisodes.isEmpty) {
          _hasError = true;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestToken != _feedRequestToken) return;
      setState(() {
        if (_podcastShows.isEmpty && _podcastEpisodes.isEmpty) {
          _hasError = true;
        }
        _isLoading = false;
      });
    }
  }

  void _schedulePreWarm(List<Song> songs, int requestToken) {
    _preWarmTimer?.cancel();
    _preWarmTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || requestToken != _feedRequestToken) return;
      for (final s in songs.take(2)) {
        StreamResolverService.preWarm(s.id, songTitle: s.title, artist: s.artist);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;
    final isPodcastsMode = _activeMood == 'Podcasts';

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

    final Widget bodyContent;
    if (_isLoading) {
      // Render skeleton directly outside RefreshIndicator so no overlapping spinner appears.
      bodyContent = isPodcastsMode
          ? const PodcastsFeedSkeleton(
              key: ValueKey('podcasts_skeleton'),
              showMoodChips: false,
            )
          : const HomeFeedSkeleton(
              key: ValueKey('home_skeleton'),
              showMoodChips: false,
            );
    } else {
      final Widget loadedOrErrorChild;
      if (isPodcastsMode) {
        loadedOrErrorChild =
            (_hasError || (_podcastShows.isEmpty && _podcastEpisodes.isEmpty))
                ? _buildErrorState(
                    theme,
                    colorScheme,
                    bottomPadding,
                    isPodcasts: true,
                  )
                : _buildPodcastsListView(theme, colorScheme, bottomPadding);
      } else if (_hasError && _quickPicks.isEmpty) {
        loadedOrErrorChild = _buildErrorState(
          theme,
          colorScheme,
          bottomPadding,
          isPodcasts: false,
        );
      } else {
        loadedOrErrorChild = ListView(
          key: const ValueKey('home_content'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            const SizedBox(height: 18),
            _buildSectionTitle('Quick Picks', theme, colorScheme),
            const SizedBox(height: 6),
            if (quickPickColumns > 0)
              LayoutBuilder(
                builder: (context, constraints) {
                  final colWidth =
                      (constraints.maxWidth * 0.91).clamp(280.0, 420.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(
                        quickPickColumns,
                        (colIndex) {
                          final start = colIndex * 4;
                          final end =
                              (start + 4).clamp(0, quickPickPool.length);
                          final colSongs = quickPickPool.sublist(start, end);
                          return SizedBox(
                            width: colWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: colSongs
                                  .map(
                                    (song) => SongTile(
                                      song: song,
                                      contextQueue: _quickPicks,
                                      contentPadding: const EdgeInsets.fromLTRB(
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
            if (albumItems.isNotEmpty && featuredNonAlbums.isNotEmpty) ...[
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
        );
      }

      bodyContent = RefreshIndicator(
        onRefresh: () {
          if (!_isLoading) {
            unawaited(_loadFeed(_activeMood, true));
          }
          return Future<void>.value();
        },
        child: loadedOrErrorChild,
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildBrandHeader(theme, colorScheme),
            _buildMoodChips(colorScheme),
            Expanded(child: bodyContent),
          ],
        ),
      ),
    );
  }

  Widget _buildPodcastsListView(
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    return ListView(
      key: const ValueKey('podcasts_content'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
        if (_podcastShows.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildSectionTitle('Podcast Shows', theme, colorScheme),
          const SizedBox(height: 12),
          _buildBrowseShelf(_podcastShows, isPodcastShelf: true),
        ],
        if (_podcastEpisodes.isNotEmpty) ...[
          SizedBox(height: _podcastShows.isNotEmpty ? 22 : 18),
          _buildSectionTitle('Podcast Episodes', theme, colorScheme),
          const SizedBox(height: 8),
          ...List.generate(
            _podcastEpisodes.length,
            (i) => SongTile(
              song: _podcastEpisodes[i],
              contextQueue: _podcastEpisodes,
              index: i,
            ),
          ),
        ],
      ],
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
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
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

  Widget _buildBrowseShelf(
    List<BrowseMediaItem> items, {
    bool isPodcastShelf = false,
  }) {
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
          final isPod = isPodcastShelf || item.type == 'podcast';
          return MediaCard(
            size: 138,
            title: item.title,
            subtitle: item.subtitle,
            imageUrl: item.thumbnailUrl,
            fallbackIcon: isPod ? Icons.podcasts_rounded : null,
            onTap: () {
              final browseId = item.browseId ?? item.id;
              if (browseId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CollectionDetailScreen(
                    browseId: browseId,
                    isAlbum: !isPod && item.type == 'album',
                    isPodcast: isPod,
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
    double bottomPadding, {
    bool isPodcasts = false,
  }) {
    return Center(
      key: ValueKey(isPodcasts ? 'podcasts_error' : 'home_error'),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 48, 24, bottomPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPodcasts ? Icons.podcasts_rounded : Icons.wifi_off_rounded,
              size: 56,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              isPodcasts
                  ? 'Unable to load podcasts'
                  : 'Unable to load music feed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isPodcasts
                  ? 'Check your internet connection or try again.'
                  : 'Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _loadFeed(_activeMood, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
