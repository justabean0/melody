import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/search_result.dart';
import '../../models/song.dart';
import '../../providers/search_provider.dart';
import '../../providers/playback_provider.dart';
import '../components/song_tile.dart';
import '../components/album_card.dart';
import '../components/top_result_play_button.dart';
import '../../widgets/skeleton_loaders.dart';
import 'collection_detail_screen.dart';
import 'artist_detail_screen.dart';
import '../../utils/thumbnail_utils.dart';

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
              child: SearchResultsSkeleton(),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                leading: Icon(
                  Icons.history_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(item),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                leading: Icon(
                  Icons.history_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(item),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                leading: const Icon(Icons.search_rounded),
                title: Text(suggestion),
                trailing: IconButton(
                  icon: const Icon(Icons.north_west, size: 18),
                  tooltip: 'Insert',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
                  onPressed: () {
                    _controller.text = suggestion;
                    search.onQueryChanged(suggestion);
                  },
                ),
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
        // Top Result Hero Card (All tab only)
        if (search.filter == SearchFilter.all && results.topResult != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Top Result',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          _buildTopResultCard(context, results.topResult, playback, theme, colorScheme),
        ],

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
                contextQueue: results.songs,
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
                contextQueue: results.videos,
              )),
        ],

        // Albums
        if (results.albums.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.albums)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Albums',
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
                  subtitle: album.year != null && album.year! > 0
                      ? '${album.artist} • ${album.year}'
                      : album.artist,
                  imageUrl: album.thumbnailUrl,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CollectionDetailScreen(
                          browseId: album.browseId,
                          isAlbum: true,
                          title: album.title,
                          subtitle: album.artist,
                          thumbnailUrl: album.thumbnailUrl,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],

        // Artists
        if (results.artists.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.artists)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Artists',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: results.artists.length,
              itemBuilder: (ctx, i) {
                final artist = results.artists[i];
                return MediaCard(
                  title: artist.name,
                  subtitle: artist.subscribers ?? 'Artist',
                  imageUrl: artist.thumbnailUrl ?? '',
                  isCircle: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailScreen(
                          browseId: artist.browseId,
                          name: artist.name,
                          thumbnailUrl: artist.thumbnailUrl,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],

        // Playlists
        if (results.playlists.isNotEmpty &&
            (search.filter == SearchFilter.all || search.filter == SearchFilter.playlists)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Playlists',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: results.playlists.length,
              itemBuilder: (ctx, i) {
                final playlist = results.playlists[i];
                return MediaCard(
                  title: playlist.title,
                  subtitle: playlist.author ?? 'Playlist',
                  imageUrl: playlist.thumbnailUrl,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CollectionDetailScreen(
                          browseId: playlist.browseId,
                          isAlbum: false,
                          title: playlist.title,
                          subtitle: playlist.author,
                          thumbnailUrl: playlist.thumbnailUrl,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopResultCard(
    BuildContext context,
    dynamic topResult,
    PlaybackProvider playback,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    String title = '';
    String subtitle = '';
    String badge = '';
    String imageUrl = '';
    bool isCircle = false;
    VoidCallback? onTap;

    if (topResult is Song) {
      title = topResult.title;
      subtitle = topResult.duration > 0
          ? '${topResult.artist} • ${topResult.formattedDuration}'
          : topResult.artist;
      badge = 'Song';
      imageUrl = topResult.thumbnailUrl;
      onTap = () {
        if (playback.currentSong?.id == topResult.id) {
          playback.togglePlayPause();
        } else {
          playback.playSong(topResult);
        }
      };
    } else if (topResult is Artist) {
      title = topResult.name;
      subtitle = topResult.subscribers ?? 'Artist';
      badge = 'Artist';
      imageUrl = topResult.thumbnailUrl ?? '';
      isCircle = true;
      onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(
              browseId: topResult.browseId,
              name: topResult.name,
              thumbnailUrl: topResult.thumbnailUrl,
            ),
          ),
        );
      };
    } else if (topResult is Album) {
      title = topResult.title;
      final yearStr = topResult.year != null && topResult.year! > 0 ? ' • ${topResult.year}' : '';
      subtitle = '${topResult.artist}$yearStr';
      badge = 'Album';
      imageUrl = topResult.thumbnailUrl;
      onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CollectionDetailScreen(
              browseId: topResult.browseId,
              isAlbum: true,
              title: topResult.title,
              subtitle: topResult.artist,
              thumbnailUrl: topResult.thumbnailUrl,
            ),
          ),
        );
      };
    } else if (topResult is Playlist) {
      title = topResult.title;
      subtitle = topResult.author ?? 'Playlist';
      badge = 'Playlist';
      imageUrl = topResult.thumbnailUrl;
      onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CollectionDetailScreen(
              browseId: topResult.browseId,
              isAlbum: false,
              title: topResult.title,
              subtitle: topResult.author,
              thumbnailUrl: topResult.thumbnailUrl,
            ),
          ),
        );
      };
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(80),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isCircle ? 36 : 10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ThumbnailUtils.upgradeUrl(imageUrl, size: 544),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              isCircle ? Icons.person : Icons.music_note,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            isCircle ? Icons.person : Icons.music_note,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (topResult is Song)
                TopResultPlayButton(song: topResult)
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
