import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../services/database_service.dart';
import '../../services/innertube_service.dart';
import '../../services/update_service.dart';
import '../components/album_card.dart';
import '../components/song_tile.dart';
import '../components/update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _quickPicks = [];
  bool _isLoading = true;
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
    _loadFeed();
    _checkAppUpdateSilently();
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

  Future<void> _loadFeed([String mood = 'All']) async {
    setState(() => _isLoading = true);
    try {
      final songs = await InnerTubeService.getQuickPicks();
      setState(() {
        _quickPicks = songs;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Melody',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadFeed(_activeMood),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                            onSelected: (val) {
                              setState(() => _activeMood = mood);
                              _loadFeed(mood);
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
                        Text(
                          'Quick Picks',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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

                  // Quick picks list
                  ..._quickPicks.take(5).map((song) => SongTile(
                        song: song,
                        contextQueue: _quickPicks,
                      )),

                  const SizedBox(height: 20),

                  // Section 2: Recommended Albums & Playlists
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
                    height: 200,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      children: [
                        MediaCard(
                          title: 'Global Top 50',
                          subtitle: 'YouTube Music',
                          imageUrl: 'https://picsum.photos/seed/yt50/300/300',
                          onTap: () {
                            if (_quickPicks.isNotEmpty) {
                              playback.playSong(_quickPicks.first, contextQueue: _quickPicks);
                            }
                          },
                        ),
                        MediaCard(
                          title: 'Lo-Fi Chill Beats',
                          subtitle: 'Focus & Study',
                          imageUrl: 'https://picsum.photos/seed/lofi/300/300',
                          onTap: () {},
                        ),
                        MediaCard(
                          title: 'Pop Rewind',
                          subtitle: 'Chartbusters',
                          imageUrl: 'https://picsum.photos/seed/pop/300/300',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Section 3: More Recommendations
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    child: Text(
                      'More For You',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  ..._quickPicks.skip(5).map((song) => SongTile(
                        song: song,
                        contextQueue: _quickPicks,
                      )),
                ],
              ),
      ),
    );
  }
}
