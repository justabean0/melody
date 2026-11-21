import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/library_provider.dart';
import '../screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final song = playback.currentSong;

    if (song == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final library = context.watch<LibraryProvider>();
    final isLiked = library.isLiked(song.id);

    // Progress percentage
    final double progress = (playback.isLoading || playback.duration.inMilliseconds <= 0)
        ? 0.0
        : (playback.position.inMilliseconds / playback.duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PlayerScreen(),
              fullscreenDialog: true,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: song.thumbnailUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title & Artist
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
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Like button
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => library.toggleLike(song),
                      ),
                      // Play/Pause button with non-blocking loading indicator
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (playback.isLoading)
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(7.0),
                                  child: IgnorePointer(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.primary.withAlpha(220),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: Icon(
                                playback.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                                color: colorScheme.onSurface,
                              ),
                              onPressed: playback.togglePlayPause,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Linear Progress bar
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2.5,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
