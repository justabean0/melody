import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<PlaybackProvider, Song?>(
      selector: (_, playback) => playback.currentSong,
      builder: (context, song, _) {
        if (song == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = colorScheme.brightness == Brightness.dark;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PlayerScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Ink(
              decoration: BoxDecoration(
                gradient: ThemeProvider.miniPlayerGradient(colorScheme),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? colorScheme.primary.withValues(alpha: 0.18)
                      : colorScheme.outlineVariant.withValues(alpha: 0.55),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.44)
                        : colorScheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 8, 6),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: song.hasRemoteThumbnail
                              ? CachedNetworkImage(
                                  imageUrl: song.thumbnailUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 44,
                                  height: 44,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: colorScheme.primary,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _MiniPlayerPlayPauseButton(),
                        IconButton(
                          tooltip: 'Next track',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 24,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: () =>
                              context.read<PlaybackProvider>().playNext(),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: _MiniPlayerProgressTrack(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerPlayPauseButton extends StatelessWidget {
  const _MiniPlayerPlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Selector<PlaybackProvider, ({bool isPlaying, bool isLoading})>(
      selector: (_, playback) => (
        isPlaying: playback.isPlaying,
        isLoading: playback.isLoading,
      ),
      builder: (context, state, _) {
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (state.isLoading)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IgnorePointer(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: state.isPlaying ? 'Pause' : 'Play',
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 22,
                  color: colorScheme.onPrimary,
                ),
                onPressed: () =>
                    context.read<PlaybackProvider>().togglePlayPause(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniPlayerProgressTrack extends StatelessWidget {
  const _MiniPlayerProgressTrack();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Selector<PlaybackProvider,
        ({Duration position, Duration duration, bool isLoading})>(
      selector: (_, playback) => (
        position: playback.position,
        duration: playback.duration,
        isLoading: playback.isLoading,
      ),
      builder: (_, state, __) {
        final double progress =
            (state.isLoading || state.duration.inMilliseconds <= 0)
                ? 0.0
                : (state.position.inMilliseconds /
                        state.duration.inMilliseconds)
                    .clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 3,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.18),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  heightFactor: 1.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
