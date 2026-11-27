import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/audio_service.dart';
import '../../services/download_service.dart';
import '../../services/innertube_service.dart';
import '../../utils/thumbnail_utils.dart';
import '../components/lyrics_view.dart';
import '../components/song_tile.dart';
import 'artist_detail_screen.dart';

class PlayerScreen extends StatefulWidget {
  final DownloadService? downloadService;

  const PlayerScreen({super.key, this.downloadService});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DownloadService _downloadService;
  double _dragValue = -1.0;
  String? _activeSongId;
  double _playbackSpeed = 1.0;
  bool _isResolvingArtist = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _downloadService = widget.downloadService ?? DownloadService();
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.downloadService != oldWidget.downloadService) {
      _downloadService = widget.downloadService ?? DownloadService();
    }
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

  List<String> _splitArtistNames(String displayArtist) {
    return displayArtist
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
  }

  Future<void> _onArtistTapped(
    Song song,
    String displayArtist,
    List<String> artistNames,
  ) async {
    if (artistNames.isEmpty ||
        displayArtist.toLowerCase() == 'unknown artist' ||
        displayArtist.toLowerCase() == 'unknown') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Artist details unavailable for this track.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (artistNames.length == 1) {
      await _openArtistDetail(
        artistNames.first,
        songId: song.id,
        artistId: song.artistId,
      );
      return;
    }

    await _showArtistPickerSheet(context, song, artistNames);
  }

  Future<void> _showArtistPickerSheet(
    BuildContext context,
    Song song,
    List<String> artistNames,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Artists',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              ...artistNames.asMap().entries.map((entry) {
                final index = entry.key;
                final name = entry.value;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  minTileHeight: 52,
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.surfaceContainerHigh,
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _openArtistDetail(
                      name,
                      songId: song.id,
                      artistId: index == 0 ? song.artistId : null,
                    );
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openArtistDetail(
    String artistName, {
    required String songId,
    String? artistId,
  }) async {
    final directId = artistId?.trim();
    if (directId != null && directId.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen(
            browseId: directId,
            name: artistName,
          ),
        ),
      );
      return;
    }

    if (_isResolvingArtist) return;
    setState(() => _isResolvingArtist = true);

    Artist? resolved;
    try {
      resolved = await InnerTubeService.resolveArtistByName(artistName);
    } catch (_) {
      resolved = null;
    }

    if (!mounted) return;
    setState(() => _isResolvingArtist = false);

    if (_activeSongId != songId) return;

    if (resolved != null && resolved.browseId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen(
            browseId: resolved!.browseId,
            name: resolved.name.isNotEmpty ? resolved.name : artistName,
            thumbnailUrl: resolved.thumbnailUrl,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not load artist page for $artistName.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleDownloadTap(BuildContext context, Song song) async {
    if (song.isLocal || song.hasLocalSource) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved on device: ${song.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final current = _downloadService.stateFor(song.id);
    if (current.status == DownloadStatus.downloading) {
      return;
    }
    if (current.status == DownloadStatus.downloaded ||
        _downloadService.isSongDownloaded(song)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Already downloaded: ${song.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await _downloadService.downloadSong(song);
    if (!context.mounted) return;

    if (result.status == DownloadStatus.downloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded "${song.title}"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (result.status == DownloadStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed for "${song.title}"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline downloads will be available soon.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final colorScheme = theme.colorScheme;
        final livePlayback = sheetCtx.watch<PlaybackProvider>();

        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) => _buildQueueView(
            sheetCtx,
            livePlayback,
            theme,
            colorScheme,
            controller: scrollController,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final song = playback.currentSong;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final library = context.watch<LibraryProvider>();

    if (song != null && song.id != _activeSongId) {
      _activeSongId = song.id;
      _dragValue = -1.0;
      _isResolvingArtist = false;
    }

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song playing')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 52,
        titleSpacing: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Minimize player',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: SizedBox(
            width: double.infinity,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              labelColor: colorScheme.onSurface,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              labelStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Now Playing', maxLines: 1),
                      ),
                    ),
                  ),
                ),
                Tab(
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Lyrics', maxLines: 1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: const [
          SizedBox(width: 52),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildPlayerView(context, playback, library, theme, colorScheme),
            const LyricsView(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerView(
    BuildContext context,
    PlaybackProvider playback,
    LibraryProvider library,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final song = playback.currentSong!;
    final isLiked = library.isLiked(song.id);
    final cleanedArtist = InnerTubeService.cleanArtistText(song.artist);
    final displayArtist =
        cleanedArtist.isNotEmpty ? cleanedArtist : 'Unknown Artist';
    final artistNames = _splitArtistNames(displayArtist);

    final accurateDuration = playback.duration > Duration.zero
        ? playback.duration
        : Duration(seconds: song.duration);
    final totalDuration = accurateDuration.inMilliseconds.toDouble();
    final currentPos = _dragValue >= 0.0
        ? _dragValue
        : (playback.isLoading
            ? 0.0
            : playback.position.inMilliseconds
                .toDouble()
                .clamp(0.0, totalDuration > 0 ? totalDuration : 1.0));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
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
                    child: song.hasRemoteThumbnail
                        ? CachedNetworkImage(
                            imageUrl: ThumbnailUtils.upgradeUrl(
                              song.thumbnailUrl,
                              size: 1080,
                            ),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 80,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 80,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Left-aligned Song Title
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              song.title,
              textAlign: TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Tappable left-aligned Artist + 4 borderless theme-colored icon actions
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Open artist $displayArtist',
                  child: InkWell(
                    key: const Key('player_artist_button'),
                    onTap: _isResolvingArtist
                        ? null
                        : () => _onArtistTapped(
                              song,
                              displayArtist,
                              artistNames,
                            ),
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                displayArtist,
                                textAlign: TextAlign.start,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (_isResolvingArtist) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PlayerActionIconsRow(
                song: song,
                isLiked: isLiked,
                playbackSpeed: _playbackSpeed,
                downloadService: _downloadService,
                colorScheme: colorScheme,
                onSpeedSelected: (speed) {
                  setState(() => _playbackSpeed = speed);
                  playback.setPlaybackSpeed(speed);
                },
                onOpenQueue: () => _showQueueBottomSheet(context),
                onDownloadPressed: () => _handleDownloadTap(context, song),
                onToggleLike: () => library.toggleLike(song),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Seek Slider & Time
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14.0),
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
                            : (playback.isLoading
                                ? Duration.zero
                                : playback.position),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDuration(accurateDuration),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Main Playback Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Shuffle',
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: playback.isShuffle
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: playback.toggleShuffle,
              ),
              IconButton(
                tooltip: 'Previous track',
                icon: const Icon(Icons.skip_previous_rounded, size: 38),
                onPressed: playback.playPrevious,
              ),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (playback.isLoading)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: IgnorePointer(
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.onPrimary.withAlpha(200),
                              ),
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: playback.isPlaying ? 'Pause' : 'Play',
                      iconSize: 44,
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: colorScheme.onPrimary,
                      ),
                      onPressed: playback.togglePlayPause,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next track',
                icon: const Icon(Icons.skip_next_rounded, size: 38),
                onPressed: playback.playNext,
              ),
              IconButton(
                tooltip: 'Repeat mode',
                icon: Icon(
                  playback.loopMode == MelodyLoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: playback.loopMode != MelodyLoopMode.off
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: playback.cycleLoopMode,
              ),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQueueView(
    BuildContext context,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme, {
    ScrollController? controller,
  }) {
    final currentSong = playback.currentSong;
    final queue = playback.queue;
    final currentIdx = playback.currentIndex;

    final upcoming = (currentIdx >= 0 && currentIdx + 1 < queue.length)
        ? queue.sublist(currentIdx + 1)
        : <Song>[];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 32.0),
      children: [
        if (currentSong != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Text(
              'Now Playing',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(50),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withAlpha(70),
                width: 1.5,
              ),
            ),
            child: SongTile(song: currentSong),
          ),
          const SizedBox(height: 20),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                upcoming.isNotEmpty
                    ? 'Up Next (${upcoming.length} ${upcoming.length == 1 ? 'track' : 'tracks'})'
                    : 'Up Next',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (upcoming.isNotEmpty)
                TextButton.icon(
                  onPressed: playback.clearQueue,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear Queue'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withAlpha(90),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No upcoming songs in queue',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap ⋮ on any track and select\n"Play Next" or "Add to Queue".',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withAlpha(160),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...upcoming.asMap().entries.map((entry) {
            final upcomingIndex = entry.key;
            final song = entry.value;
            final actualQueueIndex = currentIdx + 1 + upcomingIndex;

            return Dismissible(
              key: ValueKey('${song.id}_$actualQueueIndex'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red.shade700,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) {
                playback.removeFromQueue(actualQueueIndex);
              },
              child: SongTile(
                song: song,
                index: actualQueueIndex,
                contextQueue: queue,
              ),
            );
          }),
      ],
    );
  }
}

class _PlayerActionIconsRow extends StatelessWidget {
  final Song song;
  final bool isLiked;
  final double playbackSpeed;
  final DownloadService downloadService;
  final ColorScheme colorScheme;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onOpenQueue;
  final VoidCallback onDownloadPressed;
  final VoidCallback onToggleLike;

  const _PlayerActionIconsRow({
    required this.song,
    required this.isLiked,
    required this.playbackSpeed,
    required this.downloadService,
    required this.colorScheme,
    required this.onSpeedSelected,
    required this.onOpenQueue,
    required this.onDownloadPressed,
    required this.onToggleLike,
  });

  ButtonStyle _compactBorderlessStyle() {
    return IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 48),
      fixedSize: const Size(40, 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speedActive = (playbackSpeed - 1.0).abs() > 0.01;
    final buttonStyle = _compactBorderlessStyle();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Speed (borderless icon-only popup trigger)
        PopupMenuButton<double>(
          key: const Key('player_speed_button'),
          tooltip: 'Playback Speed',
          padding: EdgeInsets.zero,
          initialValue: playbackSpeed,
          onSelected: onSpeedSelected,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0.75, child: Text('0.75x')),
            PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
            PopupMenuItem(value: 1.25, child: Text('1.25x')),
            PopupMenuItem(value: 1.5, child: Text('1.5x')),
            PopupMenuItem(value: 2.0, child: Text('2.0x')),
          ],
          child: SizedBox(
            width: 40,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 22,
                  color: colorScheme.primary,
                ),
                if (speedActive)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 2. Queue
        IconButton(
          key: const Key('player_queue_button'),
          tooltip: 'Queue',
          style: buttonStyle,
          icon: Icon(
            Icons.queue_music_rounded,
            size: 22,
            color: colorScheme.primary,
          ),
          onPressed: onOpenQueue,
        ),

        // 3. Download
        ListenableBuilder(
          listenable: downloadService,
          builder: (_, __) {
            final dlState = downloadService.stateFor(song.id);
            final effectiveStatus =
                (song.isLocal || song.hasLocalSource || downloadService.isSongDownloaded(song))
                    ? DownloadStatus.downloaded
                    : dlState.status;
            final Widget icon;
            final String tooltip;

            switch (effectiveStatus) {
              case DownloadStatus.downloading:
                tooltip = 'Downloading';
                icon = SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: dlState.progress > 0 ? dlState.progress : null,
                    strokeWidth: 2.2,
                    color: colorScheme.primary,
                  ),
                );
                break;
              case DownloadStatus.downloaded:
                tooltip = 'Downloaded';
                icon = Icon(
                  Icons.download_done_rounded,
                  size: 22,
                  color: colorScheme.primary,
                );
                break;
              case DownloadStatus.failed:
                tooltip = 'Retry download';
                icon = Icon(
                  Icons.error_outline_rounded,
                  size: 22,
                  color: colorScheme.error,
                );
                break;
              case DownloadStatus.notDownloaded:
                tooltip = 'Download';
                icon = Icon(
                  Icons.download_rounded,
                  size: 22,
                  color: colorScheme.primary,
                );
                break;
            }

            return IconButton(
              key: const Key('player_download_button'),
              tooltip: tooltip,
              style: buttonStyle,
              icon: icon,
              onPressed: onDownloadPressed,
            );
          },
        ),

        // 4. Like
        IconButton(
          key: const Key('player_like_button'),
          tooltip: isLiked ? 'Remove from Favorites' : 'Add to Favorites',
          style: buttonStyle,
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 22,
            color: colorScheme.primary,
          ),
          onPressed: onToggleLike,
        ),
      ],
    );
  }
}
