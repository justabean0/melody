import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../services/database_service.dart';
import '../../services/innertube_service.dart';
import '../../services/stream_resolver_service.dart';
import '../../services/update_service.dart';
import '../components/album_card.dart';
import '../components/language_selection_dialog.dart';
import '../components/song_tile.dart';
import '../components/update_dialog.dart';

class _TrendingCategory {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String query;

  const _TrendingCategory({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.query,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _quickPicks = [];
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
    if (cached.isNotEmpty) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _quickPicks = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
    } else if (_quickPicks.isEmpty) {
      if (mounted && requestToken == _feedRequestToken) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }
    }

    // 2. Fetch fresh personalized feed with 10-second timeout guard
    try {
      final songs = await InnerTubeService.getQuickPicks(
        languages: activeLangs,
        mood: mood,
        forceRefresh: isUserRefresh || cached.isEmpty,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Feed network request timed out - falling back to cache');
          return cached;
        },
      );

      if (!mounted || requestToken != _feedRequestToken) return;

      setState(() {
        if (songs.isNotEmpty) {
          _quickPicks = songs;
          _hasError = false;
        } else if (_quickPicks.isEmpty && cached.isEmpty) {
          _hasError = true;
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

  List<_TrendingCategory> _getTrendingCategories() {
    final languages = DatabaseService.getMusicLanguages();
    final categories = <_TrendingCategory>[];

    for (final lang in languages) {
      switch (lang) {
        case 'Hindi':
          categories.add(const _TrendingCategory(
            title: 'Top 50 India',
            subtitle: 'Bollywood & Hindi Hits',
            imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
            query: 'Top 50 Hindi Songs 2026',
          ));
          categories.add(const _TrendingCategory(
            title: 'Desi Indie & Pop',
            subtitle: 'Indian Indie Charts',
            imageUrl: 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=300',
            query: 'Trending Hindi Indie Hits',
          ));
          break;
        case 'Punjabi':
          categories.add(const _TrendingCategory(
            title: 'Punjabi Hot 50',
            subtitle: 'Bhangra & Pop Hits',
            imageUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=300',
            query: 'Top Punjabi Songs 2026',
          ));
          break;
        case 'Spanish':
          categories.add(const _TrendingCategory(
            title: 'Viva Latino',
            subtitle: 'Reggaeton & Latin Pop',
            imageUrl: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=300',
            query: 'Top Spanish Hits 2026',
          ));
          break;
        case 'Korean':
          categories.add(const _TrendingCategory(
            title: 'K-Pop Daebak',
            subtitle: 'Top K-Pop Idol Hits',
            imageUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=300',
            query: 'Top K-Pop Songs 2026',
          ));
          break;
        case 'Bengali':
          categories.add(const _TrendingCategory(
            title: 'Bangla Top Hits',
            subtitle: 'Tollywood & Bangla Folk',
            imageUrl: 'https://images.unsplash.com/photo-1487180144351-b8472da7d491?w=300',
            query: 'Top Bengali Songs 2026',
          ));
          break;
        case 'Tamil':
          categories.add(const _TrendingCategory(
            title: 'Kollywood Beats',
            subtitle: 'Tamil Chartbusters',
            imageUrl: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=300',
            query: 'Top Tamil Songs 2026',
          ));
          break;
        case 'Telugu':
          categories.add(const _TrendingCategory(
            title: 'Tollywood Top 50',
            subtitle: 'Telugu Mass Melodies',
            imageUrl: 'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=300',
            query: 'Top Telugu Songs 2026',
          ));
          break;
        case 'Malayalam':
          categories.add(const _TrendingCategory(
            title: 'Mollywood Melodies',
            subtitle: 'Malayalam Hits & Indie',
            imageUrl: 'https://images.unsplash.com/photo-1514320291840-2e0a9bf2a9ae?w=300',
            query: 'Top Malayalam Songs 2026',
          ));
          break;
        case 'Japanese':
          categories.add(const _TrendingCategory(
            title: 'J-Pop & Anime',
            subtitle: 'Tokyo Top Charts',
            imageUrl: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=300',
            query: 'Top J-Pop Anime Songs 2026',
          ));
          break;
        case 'English':
        default:
          categories.add(const _TrendingCategory(
            title: 'Global Top 50',
            subtitle: 'International Hits',
            imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
            query: 'Global Top 50 Hits 2026',
          ));
          categories.add(const _TrendingCategory(
            title: 'Today’s Hot Hits',
            subtitle: 'Viral Pop & Hip-Hop',
            imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
            query: 'Top Billboard Hits 2026',
          ));
          break;
      }
    }

    if (categories.isEmpty) {
      categories.add(const _TrendingCategory(
        title: 'Global Top 50',
        subtitle: 'International Hits',
        imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
        query: 'Global Top 50 Hits 2026',
      ));
    }

    return categories;
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
                  _loadFeed(_activeMood, true);
                },
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadFeed(_activeMood, true),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _hasError && _quickPicks.isEmpty
                ? Center(
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
                              setState(() => _activeMood = mood);
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
                      itemCount: _getTrendingCategories().length,
                      itemBuilder: (context, index) {
                        final cat = _getTrendingCategories()[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: MediaCard(
                            title: cat.title,
                            subtitle: cat.subtitle,
                            imageUrl: cat.imageUrl,
                            onTap: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Playing ${cat.title}...'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                              try {
                                final results = await InnerTubeService.search(cat.query);
                                if (results.songs.isNotEmpty && mounted) {
                                  playback.playSong(results.songs.first, contextQueue: results.songs);
                                }
                              } catch (_) {}
                            },
                          ),
                        );
                      },
                    ),
                  ),

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
    );
  }
}
