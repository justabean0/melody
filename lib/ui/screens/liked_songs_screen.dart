import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../components/song_tile.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final ValueNotifier<String?> _openSwipeRowId = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _openSwipeRowId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final playback = context.read<PlaybackProvider>();
    final liked = library.likedSongs;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = 24.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Favourite Songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              '${liked.length} ${liked.length == 1 ? 'song' : 'songs'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (liked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.tonalIcon(
                key: const Key('liked_songs_play_all_button'),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play All'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () {
                  if (playback.isShuffle) {
                    playback.toggleShuffle();
                  }
                  playback.playSong(
                    liked.first,
                    contextQueue: liked,
                    startIndex: 0,
                  );
                },
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: liked.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.favorite_border_rounded,
                          size: 32,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No favourite songs yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap the heart icon on any track to save it to your Favourite Songs.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(0, 8, 0, bottomPadding),
                itemCount: liked.length,
                itemBuilder: (_, index) {
                  final song = liked[index];
                  return SwipeToRevealDelete(
                    key: ValueKey('liked_swipe_${song.id}'),
                    rowId: song.id,
                    openRowId: _openSwipeRowId,
                    backgroundColor: colorScheme.surface,
                    deleteTooltip: 'Remove from Favourite Songs',
                    onDelete: () => library.toggleLike(song),
                    child: SongTile(
                      song: song,
                      contextQueue: liked,
                      index: index,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
