import 'dart:async';
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
    _checkAppUpdateSilently();
    _initializeHome();
  }

  @override
  void dispose() {
    _preWarmTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeHome() async {
    final hasLangs = DatabaseService.hasSelectedMusicLanguages();
    final onboardingDone = DatabaseService.hasCompletedLanguageOnboarding();

    if (!hasLangs && !onboardingDone) {
      // Prompt user for language selection on first run before loading feed
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _checkFirstTimeLanguageSetup();
        if (mounted) {
          await _loadFeed('All', false);
        }
      });
    } else {
      // Languages already selected or onboarding completed: load immediately
      _loadFeed('All', false);
    }
  }

  Future<void> _checkFirstTimeLanguageSetup() async {
    if (!DatabaseService.hasCompletedLanguageOnboarding()) {
      await LanguageSelectionDialog.show(
        context,
        isDismissible: false,
        onSaved: (selected) {
          // Handled upon dialog completion
        },
      );
      if (!DatabaseService.hasCompletedLanguageOnboarding()) {
        await DatabaseService.markLanguageOnboardingCompleted();
      }
    }
  }

  Future<void> _checkAppUpdateSilently() async {
    if (!DatabaseService.getAutoCheckUpdates()) return;

    // Throttle checks to at most once every 6 hours
    final lastCheck = DatabaseService.getLastUpdateCheck();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCheck < const Duration(hours: 6).inMilliseconds) return;

    await DatabaseService.setLastUpdateCheck(now);

    // Wait a brief moment after UI mounts
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
    final cacheKey = '$mood:${activeLangs.join(",")}';

    // 1. Instant display from cache (0ms perceived latency)
    final cached = DatabaseService.getCachedFeed(cacheKey);
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
        // 3. Decoupled pre-warm: Delayed by 1.5s so network is not contested during feed render
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/logo.png',
                width: 38,
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Melody',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Music Languages',
            icon: const Icon(Icons.translate_rounded),
            onPressed: () {
              LanguageSelectionDialog.show(
                context,
                isDismissible: true,
                onSaved: (selected) {
                  setState(() => _isLoading = true);
                  _loadFeed(_activeMood, true);
                },
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_isLoading) return;
          unawaited(_loadFeed(_activeMood, true));
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isLoading
              ? const HomeFeedSkeleton(key: ValueKey('home_skeleton'))
              : _hasError && _quickPicks.isEmpty
                  ? Center(
                      key: const ValueKey('home_error'),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 56, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            Text(
                              'Unable to load music feed',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Check your internet connection and try again.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                    )
                  : ListView(
                      key: const ValueKey('home_content'),
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        // Moods & Genres Filters
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            children: _moods.map((mood) {
                              final isSelected = _activeMood == mood;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: FilterChip(
                                  label: Text(mood),
                                  selected: isSelected,
                                  showCheckmark: false,
                                  onSelected: (val) {
                                    setState(() {
                                      _activeMood = mood;
                                      _isLoading = true;
                                    });
                                    _loadFeed(mood, false);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                  const SizedBox(height: 12),

                  // Section 1: Quick Picks (Melody signature feature)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quick Picks',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Trending Singles & Recommendations',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withAlpha(160),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            if (_quickPicks.isNotEmpty) {
                              playback.playSong(_quickPicks.first, contextQueue: _quickPicks);
                            }
                          },
                          icon: const Icon(Icons.play_circle_fill, size: 20),
                          label: const Text('Play all'),
                        ),
                      ],
                    ),
                  ),

                  // Quick picks list (Top 8 blended trending & personalized single songs)
                  ..._quickPicks.take(8).map((song) => SongTile(
                        song: song,
                      )),

                  const SizedBox(height: 20),

                  // Section 2: Recommended Albums & Playlists (Personalized by Languages)
                  if (_browseItems.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                      child: Text(
                        'Featured & Trending',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _browseItems.length,
                        itemBuilder: (context, index) {
                          final item = _browseItems[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: MediaCard(
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
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // Section 3: More Recommendations (if extra tracks available)
                  if (_quickPicks.length > 8) ...[
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                      child: Text(
                        'More For You',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ..._quickPicks.skip(8).map((song) => SongTile(
                          song: song,
                        )),
                  ],
                ],
              ),
        ),
      ),
    );
  }
}
