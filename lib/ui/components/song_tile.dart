import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../providers/library_provider.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? contextQueue;
  final int? index;
  final VoidCallback? onTap;

  const SongTile({
    super.key,
    required this.song,
    this.contextQueue,
    this.index,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final library = context.watch<LibraryProvider>();
    final isCurrent = playback.currentSong?.id == song.id;
    final isPlaying = isCurrent && playback.isPlaying;
    final isLiked = library.isLiked(song.id);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      leading: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: song.thumbnailUrl,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 50,
                height: 50,
                color: colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note),
              ),
            ),
          ),
          if (isCurrent)
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
        ],
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        '${song.artist} • ${song.formattedDuration}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
        onSelected: (value) {
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
        ],
      ),
      onTap: onTap ??
          () {
            playback.playSong(
              song,
              contextQueue: contextQueue,
              startIndex: index,
            );
          },
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) {
    final library = context.read<LibraryProvider>();
    final playlists = library.playlists;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Add to Playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.add),
                ),
                title: const Text('New Playlist'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog(context, song);
                },
              ),
              const Divider(),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No custom playlists yet'),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (_, i) {
                      final p = playlists[i];
                      return ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(p.title),
                        subtitle: Text('${p.songs.length} tracks'),
                        onTap: () {
                          library.addSongToPlaylist(p.id, song);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to ${p.title}')),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, Song song) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                final library = context.read<LibraryProvider>();
                await library.createPlaylist(title);
                if (library.playlists.isNotEmpty) {
                  await library.addSongToPlaylist(library.playlists.last.id, song);
                }
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created playlist $title')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
