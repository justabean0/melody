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
                    showCheckmark: false,
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

          // Search Suggestions & Search History (while typing or when idle)
          if (!search.hasSearched)
            Expanded(
              child: _buildSearchSuggestionsOrHistory(context, search, theme, colorScheme),
            )
          else if (search.isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: _buildSearchResults(context, search, playback, theme, colorScheme),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestionsOrHistory(
    BuildContext context,
    SearchProvider search,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final queryText = _controller.text.trim();
    final matchingHistory = search.getMatchingHistory(queryText);
    final suggestions = search.suggestions;

    // 1. Idle state: User has not typed anything
    if (queryText.isEmpty) {
      if (search.history.isEmpty) {
        return Center(
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
        );
      }

      // Show persistent Search History with distinct history icons
      return ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                TextButton(
                  onPressed: () => search.clearHistory(),
                  child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          ...search.history.map((item) => ListTile(
                leading: Icon(
                  Icons.history_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(item),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: () => search.removeFromHistory(item),
                ),
                onTap: () {
                  _controller.text = item;
                  search.performSearch(item);
                },
              )),
        ],
      );
    }

    // 2. Active typing: Interleave matching history with fresh online suggestions
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Matching search history entries (Distinct history icon)
        if (matchingHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(
              'From History',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 11,
              ),
            ),
          ),
          ...matchingHistory.take(4).map((item) => ListTile(
                leading: Icon(
                  Icons.history_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(item),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => search.removeFromHistory(item),
                ),
                onTap: () {
                  _controller.text = item;
                  search.performSearch(item);
                },
              )),
        ],

        // Online suggestions (Magnifying glass icon)
        if (suggestions.isNotEmpty) ...[
          if (matchingHistory.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text(
                'Suggestions',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ...suggestions.map((suggestion) => ListTile(
                leading: const Icon(Icons.search_rounded),
                title: Text(suggestion),
                trailing: const Icon(Icons.north_west, size: 18),
                onTap: () {
                  _controller.text = suggestion;
                  search.performSearch(suggestion);
                },
              )),
        ],
      ],
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
