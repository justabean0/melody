import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/audio_service.dart';
import '../components/lyrics_view.dart';
import '../components/song_tile.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double _dragValue = -1.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final song = playback.currentSong;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final library = context.watch<LibraryProvider>();

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song playing')),
      );
    }

    final isLiked = library.isLiked(song.id);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Now Playing'),
            Tab(text: 'Lyrics'),
            Tab(text: 'Up Next'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? colorScheme.primary : null,
            ),
            onPressed: () => library.toggleLike(song),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Full Player View
          _buildPlayerView(context, playback, theme, colorScheme),
          // 2. Lyrics View
          const LyricsView(),
          // 3. Queue View
          _buildQueueView(context, playback, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildPlayerView(
    BuildContext context,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final song = playback.currentSong!;
    final totalDuration = playback.duration.inMilliseconds.toDouble();
    final currentPos = _dragValue >= 0.0
        ? _dragValue
        : playback.position.inMilliseconds.toDouble().clamp(0.0, totalDuration > 0 ? totalDuration : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Album Cover Artwork
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withAlpha(40),
                        blurRadius: 32,
                        spreadRadius: 4,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: CachedNetworkImage(
                      imageUrl: song.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note, size: 80),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Title & Artist Info
          Column(
            children: [
              Text(
                song.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Seek Slider & Time
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                  trackHeight: 4.0,
                ),
                child: Slider(
                  value: currentPos,
                  min: 0.0,
                  max: totalDuration > 0 ? totalDuration : 1.0,
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                  },
                  onChangeEnd: (val) {
                    playback.seek(Duration(milliseconds: val.toInt()));
                    setState(() {
                      _dragValue = -1.0;
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(
                        _dragValue >= 0.0
                            ? Duration(milliseconds: _dragValue.toInt())
                            : playback.position,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDuration(playback.duration),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Main Playback Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Shuffle
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: playback.isShuffle ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                onPressed: playback.toggleShuffle,
              ),

              // Previous
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 38),
                onPressed: playback.playPrevious,
              ),

              // Play / Pause / Loading
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: playback.isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: colorScheme.onPrimary,
                            strokeWidth: 3,
                          ),
                        ),
                      )
                    : IconButton(
                        iconSize: 44,
                        icon: Icon(
                          playback.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: colorScheme.onPrimary,
                        ),
                        onPressed: playback.togglePlayPause,
                      ),
              ),

              // Next
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 38),
                onPressed: playback.playNext,
              ),

              // Repeat mode
              IconButton(
                icon: Icon(
                  playback.loopMode == MelodyLoopMode.one
                      ? Icons.repeat_one_rounded
                      : playback.loopMode == MelodyLoopMode.all
                          ? Icons.repeat_rounded
                          : Icons.repeat_rounded,
                  color: playback.loopMode != MelodyLoopMode.off
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: playback.cycleLoopMode,
              ),
            ],
          ),

          // Bottom Quick Bar: Speed Selector & Quick Lyrics
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PopupMenuButton<double>(
                  tooltip: 'Playback Speed',
                  child: Chip(
                    avatar: const Icon(Icons.speed, size: 18),
                    label: const Text('Speed'),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  onSelected: (speed) => playback.setPlaybackSpeed(speed),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0.75, child: Text('0.75x')),
                    PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                    PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    PopupMenuItem(value: 1.5, child: Text('1.5x')),
                    PopupMenuItem(value: 2.0, child: Text('2.0x')),
                  ],
                ),
                const SizedBox(width: 12),
                ActionChip(
                  avatar: const Icon(Icons.lyrics_outlined, size: 18),
                  label: const Text('Lyrics'),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  onPressed: () {
                    _tabController.animateTo(1);
                  },
                ),
                const SizedBox(width: 12),
                ActionChip(
                  avatar: const Icon(Icons.queue_music, size: 18),
                  label: Text('Queue (${playback.queue.length})'),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  onPressed: () {
                    _tabController.animateTo(2);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueView(
    BuildContext context,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final queue = playback.queue;
    if (queue.isEmpty) {
      return const Center(child: Text('Queue is empty'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Playing Queue (${queue.length} tracks)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: playback.clearQueue,
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: queue.length,
            itemBuilder: (ctx, index) {
              final s = queue[index];
              return Dismissible(
                key: ValueKey('${s.id}_$index'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  playback.removeFromQueue(index);
                },
                child: SongTile(
                  song: s,
                  index: index,
                  contextQueue: queue,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
