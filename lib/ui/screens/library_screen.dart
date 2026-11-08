import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../components/song_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(text: 'Favorites (${library.likedSongs.length})'),
            Tab(text: 'Playlists (${library.playlists.length})'),
            Tab(text: 'History (${library.history.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Favorites Tab
          _buildFavoritesTab(context, library, playback, theme, colorScheme),
          // 2. Playlists Tab
          _buildPlaylistsTab(context, library, playback, theme, colorScheme),
          // 3. History Tab
          _buildHistoryTab(context, library, playback, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildFavoritesTab(
    BuildContext context,
    LibraryProvider library,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final liked = library.likedSongs;

    if (liked.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 72, color: colorScheme.onSurfaceVariant.withAlpha(90)),
            const SizedBox(height: 16),
            Text(
              'No favorite songs yet',
              style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${liked.length} songs', style: theme.textTheme.bodyMedium),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play All'),
                onPressed: () {
                  playback.playSong(liked.first, contextQueue: liked);
                },
              ),
            ],
          ),
        ),
        ...liked.map((s) => SongTile(
              song: s,
              contextQueue: liked,
            )),
      ],
    );
  }

  Widget _buildPlaylistsTab(
    BuildContext context,
    LibraryProvider library,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final playlists = library.playlists;

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('Create New Playlist'),
            onPressed: () => _showCreatePlaylistDialog(context, library),
          ),
        ),
        if (playlists.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No custom playlists yet.\nCreate one to organize your music!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...playlists.map((p) => ListTile(
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.queue_music, color: colorScheme.onPrimaryContainer),
                ),
                title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${p.songs.length} songs • ${p.author ?? "User"}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => library.deletePlaylist(p.id),
                ),
                onTap: () {
                  _showPlaylistDetails(context, p, playback, library);
                },
              )),
      ],
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    LibraryProvider library,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final history = library.history;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 72, color: colorScheme.onSurfaceVariant.withAlpha(90)),
            const SizedBox(height: 16),
            Text(
              'No playback history yet',
              style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${history.length} recently played', style: theme.textTheme.bodyMedium),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear'),
                onPressed: library.clearHistory,
              ),
            ],
          ),
        ),
        ...history.map((s) => SongTile(
              song: s,
              contextQueue: history,
            )),
      ],
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, LibraryProvider library) {
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('${playlist.songs.length} tracks'),
                    ],
                  ),
                  if (playlist.songs.isNotEmpty)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play All'),
                      onPressed: () {
                        playback.playSong(playlist.songs.first, contextQueue: playlist.songs);
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
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
