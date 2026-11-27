import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../../services/download_service.dart';
import '../../services/local_audio_service.dart';
import '../../utils/thumbnail_utils.dart';
import '../components/song_tile.dart';
import 'liked_songs_screen.dart';

class LibraryScreen extends StatefulWidget {
  final LocalAudioService? localAudioService;
  final DownloadService? downloadService;

  const LibraryScreen({
    super.key,
    this.localAudioService,
    this.downloadService,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playback = context.read<PlaybackProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clean Library header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Library',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 19),

            // Pill 3-tab bar + subtle 1px hairline divider beneath
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerLow
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  splashBorderRadius: BorderRadius.circular(18),
                  indicator: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  labelColor: colorScheme.onPrimary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Playlists'),
                    Tab(text: 'Local'),
                  ],
                ),
              ),
            ),
            Container(
              height: 1,
              color: colorScheme.outlineVariant
                  .withValues(alpha: isDark ? 0.25 : 0.45),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(
                    context,
                    library,
                    playback,
                    theme,
                    colorScheme,
                    bottomPadding,
                  ),
                  _buildPlaylistsTab(
                    context,
                    library,
                    playback,
                    theme,
                    colorScheme,
                    bottomPadding,
                  ),
                  _LocalMusicTab(
                    bottomPadding: bottomPadding,
                    localAudioService: widget.localAudioService,
                    downloadService: widget.downloadService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    LibraryProvider library,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    final liked = library.likedSongs;
    final history = library.history;
    final isDark = colorScheme.brightness == Brightness.dark;
    final heroColor = isDark
        ? Color.lerp(
            colorScheme.surfaceContainerLow,
            colorScheme.primaryContainer,
            0.42,
          )!
        : colorScheme.primaryContainer.withValues(alpha: 0.55);

    return ListView(
      padding: EdgeInsets.fromLTRB(0, 20, 0, bottomPadding),
      children: [
        // Hero Liked Songs Card (card body opens LikedSongsScreen; Play plays sequentially)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: heroColor,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              key: const Key('library_liked_songs_card'),
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LikedSongsScreen(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    _LikedArtworkBadge(colorScheme: colorScheme),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Liked Songs',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${liked.length} ${liked.length == 1 ? 'song' : 'songs'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: IconButton.filled(
                          tooltip: 'Play Liked Songs',
                          onPressed: liked.isNotEmpty
                              ? () {
                                  if (playback.isShuffle) {
                                    playback.toggleShuffle();
                                  }
                                  playback.playSong(
                                    liked.first,
                                    contextQueue: liked,
                                    startIndex: 0,
                                  );
                                }
                              : null,
                          style: IconButton.styleFrom(
                            fixedSize: const Size(46, 46),
                            minimumSize: const Size(46, 46),
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            disabledBackgroundColor:
                                colorScheme.primary.withValues(alpha: 0.28),
                            disabledForegroundColor:
                                colorScheme.onPrimary.withValues(alpha: 0.55),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Monthly Listening Time Sparkline Card (live via LibraryProvider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    size: 22,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: library.monthlyListeningLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        TextSpan(
                          text: ' played this month',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  height: 40,
                  child: CustomPaint(
                    painter: _ListeningSparklinePainter(
                      series: library.dailyListeningSeries,
                      lineColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // History Section (replacing Recently Liked)
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 52,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 12),
                Text(
                  'No playback history yet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'History',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: library.clearHistory,
                ),
              ],
            ),
          ),
          ...List.generate(
            history.length,
            (i) => SongTile(
              song: history[i],
              contextQueue: history,
              index: i,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaylistsTab(
    BuildContext context,
    LibraryProvider library,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    final playlists = library.playlists;

    if (playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding * 0.65),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  size: 30,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No custom playlists yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create one to organize your music',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create Playlist'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: () => _showCreatePlaylistDialog(context, library),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
      children: [
        // Balanced action row directly under tab bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Your Playlists · ${playlists.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: 'Create new playlist',
              button: true,
              child: Tooltip(
                message: 'New Playlist',
                child: InkWell(
                  onTap: () => _showCreatePlaylistDialog(context, library),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 22,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...playlists.map((p) {
          final hasRemoteCover = p.songs.isNotEmpty && p.songs.first.hasRemoteThumbnail;
          final coverUrl = hasRemoteCover
              ? ThumbnailUtils.upgradeUrl(p.songs.first.thumbnailUrl, size: 544)
              : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showPlaylistDetails(context, p, playback, library),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: coverUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  width: 56,
                                  height: 56,
                                  color: colorScheme.primaryContainer,
                                ),
                                errorWidget: (_, __, ___) =>
                                    _playlistArtFallback(colorScheme),
                              )
                            : _playlistArtFallback(colorScheme),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${p.songs.length} ${p.songs.length == 1 ? 'song' : 'songs'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        onSelected: (val) {
                          if (val == 'open') {
                            _showPlaylistDetails(context, p, playback, library);
                          } else if (val == 'delete') {
                            library.deletePlaylist(p.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'open',
                            child: Row(
                              children: [
                                Icon(Icons.playlist_play_rounded, size: 20),
                                SizedBox(width: 12),
                                Text('Open Playlist'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 20),
                                SizedBox(width: 12),
                                Text('Delete Playlist'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _playlistArtFallback(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.queue_music_rounded,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }

  void _showCreatePlaylistDialog(
      BuildContext context, LibraryProvider library) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter playlist title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) {
                library.createPlaylist(t);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistDetails(
    BuildContext context,
    Playlist playlist,
    PlaybackProvider playback,
    LibraryProvider library,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('${playlist.songs.length} tracks'),
                      ],
                    ),
                  ),
                  if (playlist.songs.isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play All'),
                      onPressed: () {
                        playback.playSong(
                          playlist.songs.first,
                          contextQueue: playlist.songs,
                          startIndex: 0,
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: playlist.songs.isEmpty
                  ? const Center(child: Text('Playlist is empty'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: playlist.songs.length,
                      itemBuilder: (_, i) => SongTile(
                        song: playlist.songs[i],
                        contextQueue: playlist.songs,
                        index: i,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LocalAudioFilter { all, downloads }

class _LocalMusicTab extends StatefulWidget {
  final double bottomPadding;
  final LocalAudioService? localAudioService;
  final DownloadService? downloadService;

  const _LocalMusicTab({
    required this.bottomPadding,
    this.localAudioService,
    this.downloadService,
  });

  @override
  State<_LocalMusicTab> createState() => _LocalMusicTabState();
}

class _LocalMusicTabState extends State<_LocalMusicTab>
    with WidgetsBindingObserver {
  late LocalAudioService _localAudio;
  late DownloadService _downloadService;
  _LocalAudioFilter _filter = _LocalAudioFilter.all;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localAudio = widget.localAudioService ?? LocalAudioService();
    _downloadService = widget.downloadService ?? DownloadService();
    _downloadService.addListener(_onDownloadServiceUpdated);
    unawaited(_syncPermissionAndScan());
  }

  @override
  void didUpdateWidget(covariant _LocalMusicTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localAudioService != oldWidget.localAudioService) {
      _localAudio = widget.localAudioService ?? LocalAudioService();
    }
    if (widget.downloadService != oldWidget.downloadService) {
      _downloadService.removeListener(_onDownloadServiceUpdated);
      _downloadService = widget.downloadService ?? DownloadService();
      _downloadService.addListener(_onDownloadServiceUpdated);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _downloadService.removeListener(_onDownloadServiceUpdated);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPermissionAndScan());
    }
  }

  void _onDownloadServiceUpdated() {
    if (!mounted) return;
    if (_localAudio.hasPermission) {
      unawaited(_localAudio.scanLocalAudio());
    }
  }

  Future<void> _syncPermissionAndScan() async {
    final status = await _localAudio.getPermissionStatus();
    if (status.granted) {
      await _localAudio.scanLocalAudio();
      await _downloadService.reconcileWithMediaStore();
    }
    if (mounted && !_initialized) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _handleGrantAccess() async {
    final status = await _localAudio.requestAudioPermission();
    if (status.granted) {
      await _downloadService.reconcileWithMediaStore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();

    return ListenableBuilder(
      listenable: _localAudio,
      builder: (_, __) {
        if (!_localAudio.hasPermission) {
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                widget.bottomPadding * 0.65,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.primaryContainer.withValues(alpha: 0.72),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: 30,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Access Local Music',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Melody scans your downloaded songs in Music/Melody and audio files saved on this device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_localAudio.isPermanentlyDenied)
                      FilledButton.tonalIcon(
                        key: const Key('local_open_settings_button'),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Open Settings'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onPressed: _localAudio.openAppSettings,
                      )
                    else
                      FilledButton.tonalIcon(
                        key: const Key('local_grant_access_button'),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Grant Access'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onPressed: _handleGrantAccess,
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final allTracks = _localAudio.tracks;
        final melodyDownloads =
            allTracks.where((t) => t.isMelodyDownload).toList();
        final deviceAudio =
            allTracks.where((t) => !t.isMelodyDownload).toList();
        final showFilterChips =
            melodyDownloads.isNotEmpty && deviceAudio.isNotEmpty;

        final activeTracks = (!showFilterChips || _filter == _LocalAudioFilter.all)
            ? allTracks
            : melodyDownloads;
        final songs = activeTracks.map((t) => t.toSong()).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(0, 14, 0, widget.bottomPadding),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'} on device',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('local_refresh_button'),
                    tooltip: 'Refresh local audio',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _localAudio.isScanning
                        ? null
                        : () => _localAudio.scanLocalAudio(),
                    icon: _localAudio.isScanning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
            ),
            if (showFilterChips)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('All (${allTracks.length})'),
                      selected: _filter == _LocalAudioFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _LocalAudioFilter.all),
                    ),
                    ChoiceChip(
                      label: Text('Downloads (${melodyDownloads.length})'),
                      selected: _filter == _LocalAudioFilter.downloads,
                      onSelected: (_) =>
                          setState(() => _filter = _LocalAudioFilter.downloads),
                    ),
                  ],
                ),
              ),
            if (songs.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.audiotrack_rounded,
                      size: 52,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No local audio found',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tracks downloaded in Melody appear in Music/Melody.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(
                songs.length,
                (i) => SongTile(
                  song: songs[i],
                  contextQueue: songs,
                  index: i,
                  onTap: () {
                    if (playback.isShuffle) {
                      playback.toggleShuffle();
                    }
                    playback.playSong(
                      songs[i],
                      contextQueue: songs,
                      startIndex: i,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LikedArtworkBadge extends StatelessWidget {
  final ColorScheme colorScheme;

  const _LikedArtworkBadge({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final startColor = Color.lerp(colorScheme.primary, Colors.deepPurple, 0.35)!;
    final midColor = colorScheme.primary;
    final endColor = Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.5)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 76,
        height: 76,
        child: CustomPaint(
          painter: _LikedSunsetMountainPainter(
            colors: [startColor, midColor, endColor],
          ),
          child: const Center(
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _LikedSunsetMountainPainter extends CustomPainter {
  final List<Color> colors;

  const _LikedSunsetMountainPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Subtle sunset disc
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      size.width * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );

    // Back mountain ridge
    final ridge1 = Path()
      ..moveTo(0, size.height * 0.76)
      ..lineTo(size.width * 0.26, size.height * 0.52)
      ..lineTo(size.width * 0.46, size.height * 0.70)
      ..lineTo(size.width * 0.68, size.height * 0.47)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      ridge1,
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    // Front mountain ridge
    final ridge2 = Path()
      ..moveTo(0, size.height * 0.84)
      ..lineTo(size.width * 0.34, size.height * 0.63)
      ..lineTo(size.width * 0.58, size.height * 0.79)
      ..lineTo(size.width * 0.82, size.height * 0.59)
      ..lineTo(size.width, size.height * 0.82)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      ridge2,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _LikedSunsetMountainPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _ListeningSparklinePainter extends CustomPainter {
  final List<int> series;
  final Color lineColor;

  const _ListeningSparklinePainter({
    required this.series,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final values = series.length >= 2 ? series : const [0, 0, 0, 0];
    final maxVal = values.fold<int>(0, math.max);
    final padX = 5.0;
    final topY = 7.0;
    final bottomY = size.height - 6.0;
    final usableW = size.width - padX * 2;
    final usableH = bottomY - topY;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = padX + (usableW * i / (values.length - 1));
      final normalized = maxVal <= 0 ? 0.0 : (values[i] / maxVal).clamp(0.0, 1.0);
      final y = bottomY - (normalized * usableH);
      points.add(Offset(x, y));
    }

    // Smooth Catmull-Rom spline converted to cubic Bezier segments with vertical clamping
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final c1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final c1y = (p1.dy + (p2.dy - p0.dy) / 6.0).clamp(topY, bottomY);
      final c2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final c2y = (p2.dy - (p3.dy - p1.dy) / 6.0).clamp(topY, bottomY);

      linePath.cubicTo(c1x, c1y, c2x, c2y, p2.dx, p2.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: maxVal > 0 ? 0.34 : 0.12),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(areaPath, areaPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    final end = points.last;
    canvas.drawCircle(
      end,
      5.5,
      Paint()..color = lineColor.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      end,
      3.2,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ListeningSparklinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.series.length != series.length ||
      !_listIntEquals(oldDelegate.series, series);

  static bool _listIntEquals(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
