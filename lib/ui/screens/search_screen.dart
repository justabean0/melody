import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/search_result.dart';
import '../../providers/search_provider.dart';
import '../../providers/playback_provider.dart';
import '../components/song_tile.dart';
import '../components/album_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();

    return Scaffold(
      appBar: AppBar(
        title: SearchBar(
          controller: _controller,
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHighest),
          hintText: 'Search songs, albums, artists...',
          leading: const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Icon(Icons.search),
          ),
          trailing: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  search.clear();
                },
              ),
          ],
          onChanged: (text) => search.onQueryChanged(text),
          onSubmitted: (text) => search.performSearch(text),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: SearchFilter.values.map((f) {
                final isSelected = search.filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: isSelected,
                    onSelected: (_) {
                      search.setFilter(f);
                      if (_controller.text.isNotEmpty) {
                        search.performSearch(_controller.text);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Search Suggestions (while typing)
          if (!search.hasSearched && search.suggestions.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: search.suggestions.length,
                itemBuilder: (ctx, index) {
                  final suggestion = search.suggestions[index];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(suggestion),
                    trailing: const Icon(Icons.north_west, size: 18),
                    onTap: () {
                      _controller.text = suggestion;
                      search.performSearch(suggestion);
                    },
                  );
                },
              ),
            )
          else if (search.isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (search.hasSearched)
            Expanded(
              child: _buildSearchResults(context, search, playback, theme, colorScheme),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 80,
                      color: colorScheme.onSurfaceVariant.withAlpha(80),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Search YouTube Music with Melody',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    SearchProvider search,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final results = search.results;

    if (results.isEmpty) {
      return const Center(child: Text('No results found'));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Songs
        if (results.songs.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.songs)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Songs',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...results.songs.map((s) => SongTile(
                song: s,
              )),
        ],

        // Videos
        if (results.videos.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.videos)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Videos',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...results.videos.map((s) => SongTile(
                song: s,
              )),
        ],

        // Albums
        if (results.albums.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.albums)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Albums & Playlists',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: results.albums.length,
              itemBuilder: (ctx, i) {
                final album = results.albums[i];
                return MediaCard(
                  title: album.title,
                  subtitle: album.artist,
                  imageUrl: album.thumbnailUrl,
                  onTap: () {
                    if (album.songs.isNotEmpty) {
                      playback.playSong(album.songs.first, contextQueue: album.songs);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
