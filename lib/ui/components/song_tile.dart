import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../providers/library_provider.dart';
import '../../utils/thumbnail_utils.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? contextQueue;
  final int? index;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;
  final String? removeFromPlaylistLabel;
  final VoidCallback? onRemoveFromPlaylist;

  const SongTile({
    super.key,
    required this.song,
    this.contextQueue,
    this.index,
    this.onTap,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
    this.removeFromPlaylistLabel,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final equalizerColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.primary
        : HSLColor.fromColor(colorScheme.primary).withLightness(0.72).toColor();

    return Selector<PlaybackProvider, ({bool isCurrent, bool isPlaying})>(
      selector: (_, playback) {
        final isCurrent = playback.currentSong?.id == song.id;
        return (
          isCurrent: isCurrent,
          isPlaying: isCurrent && playback.isPlaying,
        );
      },
      builder: (context, playbackState, _) {
        final isCurrent = playbackState.isCurrent;
        final isPlaying = playbackState.isPlaying;
        final isLiked = context.select<LibraryProvider, bool>(
          (library) => library.isLiked(song.id),
        );

        return ListTile(
          contentPadding: contentPadding,
          horizontalTitleGap: 12.0,
          minVerticalPadding: 4.0,
          visualDensity: const VisualDensity(vertical: -1),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: song.hasRemoteThumbnail
                    ? CachedNetworkImage(
                        imageUrl: ThumbnailUtils.upgradeUrl(song.thumbnailUrl, size: 544),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.surfaceContainerHigh,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.surfaceContainerHigh,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: colorScheme.surfaceContainerHigh,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: colorScheme.primary,
                        ),
                      ),
              ),
              if (isCurrent)
                Container(
                  key: Key('song_tile_active_overlay_${song.id}'),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: _PlayingEqualizerBars(
                      key: Key('playing_equalizer_bars_${song.id}'),
                      isPlaying: isPlaying,
                      color: equalizerColor,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
              color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            song.duration > 0 ? '${song.artist} • ${song.formattedDuration}' : song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Track options',
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onSelected: (value) {
              final playback = context.read<PlaybackProvider>();
              final library = context.read<LibraryProvider>();
              if (value == 'play_next') {
                playback.playNextInQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playing next: ${song.title}'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else if (value == 'add_queue') {
                playback.addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added to queue: ${song.title}'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else if (value == 'like') {
                library.toggleLike(song);
              } else if (value == 'add_playlist') {
                _showAddToPlaylistDialog(context, song);
              } else if (value == 'remove_from_playlist') {
                onRemoveFromPlaylist?.call();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'play_next',
                child: Row(
                  children: [
                    Icon(Icons.playlist_play_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Play Next'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_queue',
                child: Row(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Add to Queue'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'like',
                child: Row(
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? colorScheme.primary : null,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(isLiked ? 'Remove from Favorites' : 'Add to Favorites'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_playlist',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add, size: 20),
                    SizedBox(width: 12),
                    Text('Add to Playlist'),
                  ],
                ),
              ),
              if (onRemoveFromPlaylist != null)
                PopupMenuItem(
                  value: 'remove_from_playlist',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(removeFromPlaylistLabel ?? 'Remove from playlist'),
                    ],
                  ),
                ),
            ],
          ),
          onTap: onTap ??
              () {
                context.read<PlaybackProvider>().playSong(
                      song,
                      contextQueue: contextQueue,
                      startIndex: index,
                    );
              },
        );
      },
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) {
    final parentContext = context;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final sheetColors = theme.colorScheme;
        final library = sheetCtx.watch<LibraryProvider>();
        final playlists = library.playlists;
        final maxSheetHeight = MediaQuery.sizeOf(sheetCtx).height * 0.72;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'Add to Playlist',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: sheetColors.onSurface,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  minTileHeight: 52,
                  leading: CircleAvatar(
                    backgroundColor: sheetColors.primaryContainer,
                    child: Icon(
                      Icons.add_rounded,
                      color: sheetColors.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    'New Playlist',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showCreatePlaylistDialog(
                      parentContext,
                      title: 'Create Playlist',
                      initialSong: song,
                    );
                  },
                ),
                const Divider(),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'No custom playlists yet',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: sheetColors.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: playlists.length,
                      itemBuilder: (_, i) {
                        final p = playlists[i];
                        final countLabel =
                            '${p.songs.length} ${p.songs.length == 1 ? 'track' : 'tracks'}';
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          minTileHeight: 52,
                          leading: Icon(
                            Icons.playlist_play_rounded,
                            color: sheetColors.primary,
                          ),
                          title: Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            countLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: sheetColors.onSurfaceVariant,
                            ),
                          ),
                          onTap: () {
                            library.addSongToPlaylist(p.id, song);
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.maybeOf(parentContext)?.showSnackBar(
                              SnackBar(
                                content: Text('Added to ${p.title}'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shared modal dialog for creating a playlist (optionally seeding [initialSong]),
/// with proper TextEditingController disposal and non-empty validation.
Future<void> showCreatePlaylistDialog(
  BuildContext context, {
  String title = 'New Playlist',
  Song? initialSong,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _CreatePlaylistDialog(
      title: title,
      parentContext: context,
      initialSong: initialSong,
    ),
  );
}

class _CreatePlaylistDialog extends StatefulWidget {
  final String title;
  final BuildContext parentContext;
  final Song? initialSong;

  const _CreatePlaylistDialog({
    required this.title,
    required this.parentContext,
    this.initialSong,
  });

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a playlist name');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final library = context.read<LibraryProvider>();
    await library.createPlaylist(name);
    if (widget.initialSong != null && library.playlists.isNotEmpty) {
      await library.addSongToPlaylist(
        library.playlists.last.id,
        widget.initialSong!,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    if (widget.initialSong != null && widget.parentContext.mounted) {
      ScaffoldMessenger.maybeOf(widget.parentContext)?.showSnackBar(
        SnackBar(
          content: Text('Created playlist $name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty && !_isSaving;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.initialSong != null
              ? 'Playlist Name'
              : 'Enter playlist title',
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          } else {
            setState(() {});
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _PlayingEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _PlayingEqualizerBars({
    super.key,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<_PlayingEqualizerBars> createState() => _PlayingEqualizerBarsState();
}

class _PlayingEqualizerBarsState extends State<_PlayingEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _PlayingEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (widget.isPlaying && !disableAnimations) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final isAnimating = widget.isPlaying && !disableAnimations;

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: 21,
          height: 18,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => CustomPaint(
              painter: _EqualizerBarsPainter(
                progress: _controller.value,
                isPlaying: widget.isPlaying,
                isAnimating: isAnimating,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EqualizerBarsPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final bool isAnimating;
  final Color color;

  static const _barCount = 4;
  static const _phases = [0.0, 1.45, 2.8, 4.15];
  static const _staticPlayingHeights = [0.52, 0.90, 0.42, 0.74];
  static const _pausedHeights = [0.24, 0.34, 0.20, 0.30];

  const _EqualizerBarsPainter({
    required this.progress,
    required this.isPlaying,
    required this.isAnimating,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const barWidth = 3.0;
    const gap = 3.0;
    final radius = const Radius.circular(1.5);

    for (int i = 0; i < _barCount; i++) {
      final double factor;
      if (!isPlaying) {
        factor = _pausedHeights[i];
      } else if (!isAnimating) {
        factor = _staticPlayingHeights[i];
      } else {
        final angle = (progress * 2 * math.pi) + _phases[i];
        final harmonic = (progress * 4 * math.pi) + (_phases[i] * 1.3);
        factor = (0.56 + 0.30 * math.sin(angle) + 0.14 * math.cos(harmonic))
            .clamp(0.24, 1.0);
      }

      final barHeight = (size.height * factor).clamp(3.0, size.height);
      final left = i * (barWidth + gap);
      final top = size.height - barHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.isAnimating != isAnimating ||
      oldDelegate.color != color;
}

/// Horizontal swipe-left-to-reveal action wrapper for list rows.
///
/// Swiping left smoothly slides the row up to [revealWidth] (`72dp`) without
/// auto-deleting; tapping the revealed delete button invokes [onDelete].
/// Only one row coordinated by [openRowId] remains revealed at a time.
class SwipeToRevealDelete extends StatefulWidget {
  final String rowId;
  final ValueNotifier<String?> openRowId;
  final Color backgroundColor;
  final String deleteTooltip;
  final VoidCallback onDelete;
  final Widget child;
  final double revealWidth;

  const SwipeToRevealDelete({
    super.key,
    required this.rowId,
    required this.openRowId,
    required this.backgroundColor,
    required this.deleteTooltip,
    required this.onDelete,
    required this.child,
    this.revealWidth = 72.0,
  });

  @override
  State<SwipeToRevealDelete> createState() => _SwipeToRevealDeleteState();
}

class _SwipeToRevealDeleteState extends State<SwipeToRevealDelete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _isOpen => _controller.value > 0.02;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    widget.openRowId.addListener(_handleOpenRowChanged);
  }

  @override
  void didUpdateWidget(covariant SwipeToRevealDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openRowId != widget.openRowId) {
      oldWidget.openRowId.removeListener(_handleOpenRowChanged);
      widget.openRowId.addListener(_handleOpenRowChanged);
    }
  }

  @override
  void dispose() {
    widget.openRowId.removeListener(_handleOpenRowChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleOpenRowChanged() {
    if (widget.openRowId.value != widget.rowId && _isOpen) {
      _animateClosed();
    }
  }

  void _animateOpen() {
    widget.openRowId.value = widget.rowId;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    } else {
      _controller.animateTo(1.0, curve: Curves.easeOutCubic);
    }
  }

  void _animateClosed() {
    if (widget.openRowId.value == widget.rowId) {
      widget.openRowId.value = null;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.0;
    } else {
      _controller.animateTo(0.0, curve: Curves.easeOutCubic);
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (widget.openRowId.value != widget.rowId) {
      widget.openRowId.value = widget.rowId;
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final deltaFraction = -(details.primaryDelta ?? 0.0) / widget.revealWidth;
    final next = (_controller.value + deltaFraction).clamp(0.0, 1.0);
    _controller.value = next;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0.0;
    if (vx < -220) {
      _animateOpen();
    } else if (vx > 220) {
      _animateClosed();
    } else if (_controller.value >= 0.4) {
      _animateOpen();
    } else {
      _animateClosed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offsetX = -_controller.value * widget.revealWidth;
        final isRevealed = _controller.value > 0.01;
        final isInteractiveOpen = _controller.value >= 0.5;

        return Stack(
          alignment: Alignment.centerRight,
          children: [
            if (isRevealed)
              Positioned.fill(
                child: ColoredBox(
                  color: widget.backgroundColor,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: widget.revealWidth,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: !isInteractiveOpen,
                          child: Semantics(
                            label: widget.deleteTooltip,
                            button: true,
                            child: Tooltip(
                              message: widget.deleteTooltip,
                              child: Material(
                                color: colorScheme.errorContainer
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: Key('swipe_delete_button_${widget.rowId}'),
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    _animateClosed();
                                    widget.onDelete();
                                  },
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Icon(
                                      Icons.delete_outline,
                                      color: colorScheme.onErrorContainer,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(offsetX, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                onTap: isInteractiveOpen ? _animateClosed : null,
                child: AbsorbPointer(
                  absorbing: isInteractiveOpen,
                  child: ColoredBox(
                    color: widget.backgroundColor,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}
