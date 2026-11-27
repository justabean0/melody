import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../../services/database_service.dart';
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

            // Segmented 3-tab pill bar with in-place cross-fade (no sliding bullet indicator)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerLow
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AnimatedBuilder(
                  animation: _tabController.animation != null
                      ? Listenable.merge([_tabController, _tabController.animation!])
                      : _tabController,
                  builder: (context, _) {
                    final activeIndex = _tabController.indexIsChanging
                        ? _tabController.index
                        : (_tabController.animation?.value.round() ??
                                _tabController.index)
                            .clamp(0, 2);
                    return Row(
                      children: [
                        _LibrarySegmentTab(
                          key: const Key('library_tab_overview'),
                          label: 'Overview',
                          selected: activeIndex == 0,
                          onTap: () => _tabController.animateTo(0),
                        ),
                        _LibrarySegmentTab(
                          key: const Key('library_tab_playlists'),
                          label: 'Playlists',
                          selected: activeIndex == 1,
                          onTap: () => _tabController.animateTo(1),
                        ),
                        _LibrarySegmentTab(
                          key: const Key('library_tab_local'),
                          label: 'Local',
                          selected: activeIndex == 2,
                          onTap: () => _tabController.animateTo(2),
                        ),
                      ],
                    );
                  },
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
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    final history = library.history;

    return ListView(
      padding: EdgeInsets.fromLTRB(0, 20, 0, bottomPadding),
      children: [
        // Split Playtime Hero Card with expandable Daily/Monthly bar chart & play logs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PlaytimeHeroCard(library: library),
        ),

        const SizedBox(height: 20),

        // History Section
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
                  onPressed: () => _confirmClearHistory(context, library),
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
    final liked = library.likedSongs;
    final playlists = library.playlists;
    final isDark = colorScheme.brightness == Brightness.dark;
    final favCardColor = isDark
        ? Color.lerp(
            colorScheme.surfaceContainerLow,
            colorScheme.primaryContainer,
            0.42,
          )!
        : colorScheme.primaryContainer.withValues(alpha: 0.55);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
      children: [
        // Balanced action row directly under tab bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                playlists.isEmpty
                    ? 'Your Playlists'
                    : 'Your Playlists · ${playlists.length}',
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

        // Pinned default Favourite Songs playlist card (no delete button)
        Material(
          color: favCardColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const Key('library_favourite_songs_card'),
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LikedSongsScreen(),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  _LikedArtworkBadge(
                    colorScheme: colorScheme,
                    size: 56,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Favourite Songs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${liked.length} ${liked.length == 1 ? 'song' : 'songs'}',
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
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: IconButton.filled(
                        tooltip: 'Play Favourite Songs',
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
                          fixedSize: const Size(42, 42),
                          minimumSize: const Size(42, 42),
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          disabledBackgroundColor:
                              colorScheme.primary.withValues(alpha: 0.28),
                          disabledForegroundColor:
                              colorScheme.onPrimary.withValues(alpha: 0.55),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (playlists.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 28,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  'No custom playlists yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create one to organize your music',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create Playlist'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: () => _showCreatePlaylistDialog(context, library),
                ),
              ],
            ),
          )
        else
          ...playlists.map((p) {
            final hasRemoteCover =
                p.songs.isNotEmpty && p.songs.first.hasRemoteThumbnail;
            final coverUrl = hasRemoteCover
                ? ThumbnailUtils.upgradeUrl(p.songs.first.thumbnailUrl,
                    size: 544)
                : '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () =>
                      _showPlaylistDetails(context, p, playback, library),
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
                              _showPlaylistDetails(
                                  context, p, playback, library);
                            } else if (val == 'delete') {
                              _confirmDeletePlaylist(context, library, p);
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

  Future<void> _confirmClearHistory(
    BuildContext context,
    LibraryProvider library,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear playback history?'),
        content: const Text(
          'This removes all tracks from your Overview listening history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.clearHistory();
    }
  }

  Future<void> _confirmDeletePlaylist(
    BuildContext context,
    LibraryProvider library,
    Playlist playlist,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${playlist.title}"?'),
        content: const Text(
          'This playlist and its track list will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.deletePlaylist(playlist.id);
    }
  }

  void _showCreatePlaylistDialog(
      BuildContext context, LibraryProvider library) {
    showCreatePlaylistDialog(context, title: 'New Playlist');
  }

  void _showPlaylistDetails(
    BuildContext context,
    Playlist playlist,
    PlaybackProvider playback,
    LibraryProvider library,
  ) {
    final sheetColor = Theme.of(context).colorScheme.surfaceContainerLow;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PlaylistDetailsSheet(
        playlistId: playlist.id,
        initialPlaylist: playlist,
      ),
    );
  }
}

class _PlaylistDetailsSheet extends StatefulWidget {
  final String playlistId;
  final Playlist initialPlaylist;

  const _PlaylistDetailsSheet({
    required this.playlistId,
    required this.initialPlaylist,
  });

  @override
  State<_PlaylistDetailsSheet> createState() => _PlaylistDetailsSheetState();
}

class _PlaylistDetailsSheetState extends State<_PlaylistDetailsSheet> {
  final ValueNotifier<String?> _openSwipeRowId = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _openSwipeRowId.dispose();
    super.dispose();
  }

  Future<void> _removeSong(Playlist playlist, Song song) async {
    await context
        .read<LibraryProvider>()
        .removeSongFromPlaylist(playlist.id, song.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Removed "${song.title}" from ${playlist.title}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playback = context.read<PlaybackProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final sheetColor = colorScheme.surfaceContainerLow;
    final playlist = library.playlists
            .where((p) => p.id == widget.playlistId)
            .firstOrNull ??
        widget.initialPlaylist;

    return DraggableScrollableSheet(
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
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
                      Text(
                        '${playlist.songs.length} ${playlist.songs.length == 1 ? 'track' : 'tracks'}',
                      ),
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
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: playlist.songs.isEmpty
                ? SingleChildScrollView(
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      48,
                      24,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            size: 44,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Playlist is empty',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      bottom: 16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: playlist.songs.length,
                    itemBuilder: (_, i) {
                      final song = playlist.songs[i];
                      return SwipeToRevealDelete(
                        key: ValueKey('playlist_swipe_${playlist.id}_${song.id}'),
                        rowId: song.id,
                        openRowId: _openSwipeRowId,
                        backgroundColor: sheetColor,
                        deleteTooltip: 'Remove from playlist',
                        onDelete: () => _removeSong(playlist, song),
                        child: SongTile(
                          song: song,
                          contextQueue: playlist.songs,
                          index: i,
                          removeFromPlaylistLabel: 'Remove from playlist',
                          onRemoveFromPlaylist: () => _removeSong(playlist, song),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
    _initialized = _localAudio.hasPermission || _localAudio.tracks.isNotEmpty;
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
    final status = await _localAudio.getPermissionStatus().timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => AudioPermissionStatus(
            granted: _localAudio.hasPermission,
            permanentlyDenied: _localAudio.isPermanentlyDenied,
          ),
        );
    if (mounted && !_initialized) {
      setState(() => _initialized = true);
    }
    if (status.granted) {
      await _localAudio.scanLocalAudio();
      await _downloadService.reconcileWithMediaStore();
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
        if (!_initialized &&
            !_localAudio.hasPermission &&
            _localAudio.tracks.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.bottomPadding * 0.5),
              child: Semantics(
                label: 'Checking local audio permission',
                child: const CircularProgressIndicator(),
              ),
            ),
          );
        }

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
            if (songs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('local_play_all_button'),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Play All'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () {
                        if (playback.isShuffle) {
                          playback.toggleShuffle();
                        }
                        playback.playSong(
                          songs.first,
                          contextQueue: songs,
                          startIndex: 0,
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      key: const Key('local_shuffle_button'),
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Shuffle'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () {
                        final shuffled = List<Song>.from(songs)..shuffle();
                        playback.playSong(
                          shuffled.first,
                          contextQueue: shuffled,
                          startIndex: 0,
                        );
                      },
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

class _LibrarySegmentTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LibrarySegmentTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseStyle = theme.textTheme.labelLarge ?? const TextStyle();

    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: double.infinity,
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                style: baseStyle.copyWith(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LikedArtworkBadge extends StatelessWidget {
  final ColorScheme colorScheme;
  final double size;
  final double borderRadius;

  const _LikedArtworkBadge({
    required this.colorScheme,
    this.size = 56,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final startColor = Color.lerp(colorScheme.primary, Colors.deepPurple, 0.35)!;
    final midColor = colorScheme.primary;
    final endColor = Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.5)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _LikedSunsetMountainPainter(
            colors: [startColor, midColor, endColor],
          ),
          child: Center(
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: size * 0.44,
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

enum _PlaytimeScope { daily, monthly }

class _PlaytimeHeroCard extends StatefulWidget {
  final LibraryProvider library;

  const _PlaytimeHeroCard({required this.library});

  @override
  State<_PlaytimeHeroCard> createState() => _PlaytimeHeroCardState();
}

class _PlaytimeHeroCardState extends State<_PlaytimeHeroCard> {
  bool _isExpanded = false;
  bool _showAllLogs = false;
  _PlaytimeScope _scope = _PlaytimeScope.daily;
  int? _selectedBarIndex;

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (!_isExpanded) {
        _selectedBarIndex = null;
        _showAllLogs = false;
      }
    });
  }

  void _selectScope(_PlaytimeScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _selectedBarIndex = null;
    });
  }

  void _onBarTap(int index) {
    setState(() {
      _selectedBarIndex = _selectedBarIndex == index ? null : index;
    });
  }

  String _formatPlayLogTime(DateTime playedAt, DateTime now) {
    final diff = now.difference(playedAt);
    if (diff.inSeconds < 60 && !diff.isNegative) {
      return 'Just now';
    }
    if (diff.inMinutes < 60 && !diff.isNegative) {
      return '${diff.inMinutes}m ago';
    }
    final hour12 = playedAt.hour % 12 == 0 ? 12 : playedAt.hour % 12;
    final minuteStr = playedAt.minute.toString().padLeft(2, '0');
    final amPm = playedAt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:$minuteStr $amPm';

    final today = DateTime(now.year, now.month, now.day);
    final logDay = DateTime(playedAt.year, playedAt.month, playedAt.day);
    final dayDiff = today.difference(logDay).inDays;
    if (dayDiff == 0) return 'Today, $timeStr';
    if (dayDiff == 1) return 'Yesterday, $timeStr';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[playedAt.month - 1]} ${playedAt.day}, $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final library = widget.library;
    final playback = context.read<PlaybackProvider>();

    final isDaily = _scope == _PlaytimeScope.daily;
    final buckets = isDaily
        ? library.dailyPlaytimeBuckets
        : library.monthlyPlaytimeBuckets;
    final validSelectedIndex = (_selectedBarIndex != null &&
            _selectedBarIndex! >= 0 &&
            _selectedBarIndex! < buckets.length)
        ? _selectedBarIndex
        : null;
    final selectedBucket =
        validSelectedIndex != null ? buckets[validSelectedIndex] : null;

    final int activeSeconds = selectedBucket != null
        ? selectedBucket.seconds
        : (isDaily
            ? library.todayListeningSeconds
            : library.monthlyListeningSeconds);
    final split = DatabaseService.formatSplitPlaytime(activeSeconds);
    final trendSeries = buckets.map((b) => b.seconds).toList();
    final logs = library.recentPlayLogs;
    final now = DateTime.now();

    final periodTitle = selectedBucket != null
        ? selectedBucket.label
        : (isDaily ? 'Today' : 'This Month');

    return Material(
      key: const Key('library_playtime_hero_card'),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.28 : 0.45,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Collapsed split hero header (tap anywhere to expand/collapse)
            Semantics(
              label:
                  'Playtime ${split.summary}. ${_isExpanded ? 'Collapse' : 'Expand'} details',
              expanded: _isExpanded,
              button: true,
              child: InkWell(
                key: const Key('playtime_hero_toggle'),
                onTap: _toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left (~58%): Header + live trend sparkline
                      Expanded(
                        flex: 58,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Playtime',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    isDaily ? 'Daily' : 'Monthly',
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: CustomPaint(
                                key: const Key('playtime_trend_graph'),
                                painter: _ListeningSparklinePainter(
                                  series: trendSeries,
                                  lineColor: colorScheme.primary,
                                  selectedIndex: validSelectedIndex,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Subtle vertical divider
                      Container(
                        width: 1,
                        height: 76,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: colorScheme.outlineVariant.withValues(
                          alpha: isDark ? 0.32 : 0.55,
                        ),
                      ),

                      // Right (~42%): Stacked two-line counter + expand chevron
                      Expanded(
                        flex: 42,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    periodTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: selectedBucket != null
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: _isExpanded ? 0.5 : 0.0,
                                  duration: disableAnimations
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    key: const Key('playtime_expand_chevron'),
                                    size: 20,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: split.primaryValue,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.6,
                                        height: 1.05,
                                        color: colorScheme.onSurface,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' ${split.primaryUnit}',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: split.secondaryValue,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                        color: colorScheme.onSurfaceVariant,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' ${split.secondaryUnit}',
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expanded interactive bar chart & detailed play logs
            if (_isExpanded) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(
                  alpha: isDark ? 0.25 : 0.45,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlaytimeScopeChip(
                                key: const Key('playtime_scope_daily'),
                                label: 'Daily',
                                selected: isDaily,
                                onTap: () => _selectScope(_PlaytimeScope.daily),
                              ),
                              _PlaytimeScopeChip(
                                key: const Key('playtime_scope_monthly'),
                                label: 'Monthly',
                                selected: !isDaily,
                                onTap: () =>
                                    _selectScope(_PlaytimeScope.monthly),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          key: const Key('playtime_inspected_readout'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: selectedBucket != null
                              ? () => setState(() => _selectedBarIndex = null)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selectedBucket != null
                                  ? colorScheme.primaryContainer
                                      .withValues(alpha: 0.72)
                                  : colorScheme.surfaceContainerHigh
                                      .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    selectedBucket != null
                                        ? '${selectedBucket.label} • ${DatabaseService.formatCompactPlaytime(selectedBucket.seconds)}'
                                        : (isDaily
                                            ? 'Last 7 days'
                                            : 'Last 6 months'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selectedBucket != null
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                if (selectedBucket != null) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PlaytimeBarChart(
                      buckets: buckets,
                      selectedIndex: validSelectedIndex,
                      onSelectBar: _onBarTap,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Recent Play Logs',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (logs.isNotEmpty)
                          Text(
                            '${logs.length} ${logs.length == 1 ? 'session' : 'sessions'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (logs.isEmpty)
                      Container(
                        key: const Key('playtime_logs_empty'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.headphones_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No listening sessions logged yet',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        key: const Key('playtime_logs_list'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...List.generate(
                            math.min(logs.length, _showAllLogs ? 20 : 5),
                            (i) {
                              final log = logs[i];
                              return Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                                child: Semantics(
                                  button: true,
                                  label: 'Play ${log.title} by ${log.artist}',
                                  child: Material(
                                    color: colorScheme.surfaceContainerHigh
                                        .withValues(alpha: 0.42),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        playback.playSong(
                                          Song(
                                            id: log.songId,
                                            title: log.title,
                                            artist: log.artist,
                                            thumbnailUrl: log.thumbnailUrl,
                                          ),
                                        );
                                      },
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(minHeight: 52),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: log.thumbnailUrl
                                                            .isNotEmpty &&
                                                        log.thumbnailUrl
                                                            .startsWith('http')
                                                    ? CachedNetworkImage(
                                                        imageUrl: ThumbnailUtils
                                                            .upgradeUrl(
                                                          log.thumbnailUrl,
                                                          size: 226,
                                                        ),
                                                        width: 36,
                                                        height: 36,
                                                        fit: BoxFit.cover,
                                                        placeholder: (_, __) =>
                                                            Container(
                                                          width: 36,
                                                          height: 36,
                                                          color: colorScheme
                                                              .surfaceContainerHighest,
                                                        ),
                                                        errorWidget: (_, __,
                                                                ___) =>
                                                            _playLogArtFallback(
                                                                colorScheme),
                                                      )
                                                    : _playLogArtFallback(
                                                        colorScheme),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      log.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme.bodyMedium
                                                          ?.copyWith(
                                                        fontSize: 13.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: colorScheme
                                                            .onSurface,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${log.artist} • ${_formatPlayLogTime(log.playedAt, now)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        fontSize: 11.5,
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.72),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: Text(
                                                  DatabaseService
                                                      .formatCompactPlaytime(
                                                    log.durationSeconds,
                                                  ),
                                                  maxLines: 1,
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: colorScheme
                                                        .onPrimaryContainer,
                                                    fontFeatures: const [
                                                      FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (logs.length > 5) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                onPressed: () => setState(
                                  () => _showAllLogs = !_showAllLogs,
                                ),
                                child: Text(
                                  _showAllLogs
                                      ? 'Show less'
                                      : 'Show all (${math.min(logs.length, 20)})',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _playLogArtFallback(ColorScheme colorScheme) {
    return Container(
      width: 36,
      height: 36,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        size: 18,
        color: colorScheme.primary,
      ),
    );
  }
}

class _PlaytimeScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlaytimeScopeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 68),
          child: AnimatedContainer(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaytimeBarChart extends StatelessWidget {
  final List<PlaytimeBucket> buckets;
  final int? selectedIndex;
  final ValueChanged<int> onSelectBar;

  const _PlaytimeBarChart({
    required this.buckets,
    required this.selectedIndex,
    required this.onSelectBar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final maxSeconds = buckets.fold<int>(0, (prev, b) => math.max(prev, b.seconds));
    const double maxBarHeight = 96.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(buckets.length, (i) {
        final bucket = buckets[i];
        final isSelected = selectedIndex == i;
        final isCurrentBucket = selectedIndex == null && i == buckets.length - 1;
        final isHighlighted = isSelected || isCurrentBucket;

        final double barHeight;
        if (bucket.seconds <= 0 || maxSeconds <= 0) {
          barHeight = 6.0;
        } else {
          barHeight = ((bucket.seconds / maxSeconds) * maxBarHeight)
              .clamp(14.0, maxBarHeight);
        }

        final Color barColor;
        if (isSelected) {
          barColor = colorScheme.primary;
        } else if (selectedIndex != null) {
          barColor = colorScheme.primary.withValues(alpha: 0.28);
        } else if (isCurrentBucket) {
          barColor = colorScheme.primary;
        } else {
          barColor = colorScheme.primary.withValues(alpha: 0.45);
        }

        return Expanded(
          child: Semantics(
            label:
                '${bucket.label}: ${DatabaseService.formatCompactPlaytime(bucket.seconds)}',
            selected: isSelected,
            button: true,
            child: GestureDetector(
              key: Key('playtime_bar_${bucket.key}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelectBar(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: maxBarHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              width: 20,
                              height: maxBarHeight,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(
                                  alpha: colorScheme.brightness == Brightness.dark
                                      ? 0.48
                                      : 0.72,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            AnimatedContainer(
                              duration: disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: 20,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 18,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          bucket.label,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11.5,
                            fontWeight:
                                isHighlighted ? FontWeight.w700 : FontWeight.w500,
                            color: isHighlighted
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ListeningSparklinePainter extends CustomPainter {
  final List<int> series;
  final Color lineColor;
  final int? selectedIndex;

  const _ListeningSparklinePainter({
    required this.series,
    required this.lineColor,
    this.selectedIndex,
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

    final focusIdx = (selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < points.length)
        ? selectedIndex!
        : points.length - 1;
    final focusPoint = points[focusIdx];
    canvas.drawCircle(
      focusPoint,
      5.5,
      Paint()..color = lineColor.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      focusPoint,
      3.2,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ListeningSparklinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.selectedIndex != selectedIndex ||
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
