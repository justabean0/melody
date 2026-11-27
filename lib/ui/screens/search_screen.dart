import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/search_result.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../providers/search_provider.dart';
import '../../utils/thumbnail_utils.dart';
import '../../widgets/skeleton_loaders.dart';
import '../components/album_card.dart';
import '../components/song_tile.dart';
import '../components/top_result_play_button.dart';
import 'artist_detail_screen.dart';
import 'collection_detail_screen.dart';

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

  void _submitSearch(SearchProvider search, String query) {
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    search.performSearch(query);
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    SearchProvider search,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear recent searches?'),
        content: const Text(
          'This will remove all items from your search history.',
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
      await search.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;
    final textScaler = MediaQuery.textScalerOf(context);
    final searchBarMaxHeight = math.max(56.0, 32.0 + textScaler.scale(24.0));
    final chipStripHeight = math.max(48.0, 28.0 + textScaler.scale(20.0));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Direct headerless search pill (`12dp` top gap)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _controller,
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor:
                    WidgetStatePropertyAll(colorScheme.surfaceContainerHigh),
                side: const WidgetStatePropertyAll(BorderSide.none),
                constraints: BoxConstraints(
                  minHeight: 48,
                  maxHeight: searchBarMaxHeight,
                ),
                shape: const WidgetStatePropertyAll(StadiumBorder()),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.only(left: 16, right: 6),
                ),
                hintText: 'Search songs, albums, artists...',
                hintStyle: WidgetStatePropertyAll(
                  theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
                leading: Icon(
                  Icons.search_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 21,
                ),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onPressed: () {
                        _controller.clear();
                        search.clear();
                      },
                    ),
                ],
                onChanged: (text) {
                  setState(() {});
                  search.onQueryChanged(text);
                },
                onSubmitted: (text) => _submitSearch(search, text),
              ),
            ),

            // Filter Chips
            SizedBox(
              height: chipStripHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: SearchFilter.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final f = SearchFilter.values[index];
                  final isSelected = search.filter == f;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: FilterChip(
                        label: Text(
                          f.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                          ),
                        ),
                        selected: isSelected,
                        showCheckmark: false,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        selectedColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (_) {
                          if (search.filter == f) return;
                          search.setFilter(f);
                          if (_controller.text.isNotEmpty) {
                            search.performSearch(_controller.text);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // Content body
            if (!search.hasSearched)
              Expanded(
                child: _buildSearchSuggestionsOrHistory(
                  context,
                  search,
                  theme,
                  colorScheme,
                  bottomPadding,
                ),
              )
            else if (search.isLoading)
              const Expanded(
                child: SearchResultsSkeleton(),
              )
            else
              Expanded(
                child: _buildSearchResults(
                  context,
                  search,
                  playback,
                  theme,
                  colorScheme,
                  bottomPadding,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSuggestionsOrHistory(
    BuildContext context,
    SearchProvider search,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomPadding,
  ) {
    final queryText = _controller.text.trim();
    final matchingHistory = search.getMatchingHistory(queryText);
    final suggestions = search.suggestions;

    if (queryText.isEmpty) {
      if (search.history.isEmpty) {
        return Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding * 0.45),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 76,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
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
        );
      }

      return ListView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Recent Searches',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _confirmClearHistory(context, search),
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
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
                  onPressed: () => search.removeFromHistory(item),
                ),
                onTap: () => _submitSearch(search, item),
              )),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
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
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
                  onPressed: () => search.removeFromHistory(item),
                ),
                onTap: () => _submitSearch(search, item),
              )),
        ],
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
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: const EdgeInsets.all(12),
                  onPressed: () {
                    _controller.text = suggestion;
                    _controller.selection =
                        TextSelection.collapsed(offset: suggestion.length);
                    search.onQueryChanged(suggestion);
                  },
                ),
                onTap: () => _submitSearch(search, suggestion),
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
    double bottomPadding,
  ) {
    final results = search.results;

    if (results.isEmpty) {
      final hasSpecificFilter = search.filter != SearchFilter.all;
      final activeQuery = search.query.trim();
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 14),
              Text(
                activeQuery.isNotEmpty
                    ? 'No results for "$activeQuery"'
                    : 'No results found',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasSpecificFilter
                    ? 'Try searching across all categories or adjusting your keywords.'
                    : 'Check your spelling or try a different song, album, or artist.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasSpecificFilter) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () {
                    search.setFilter(SearchFilter.all);
                    final q = _controller.text.trim().isNotEmpty
                        ? _controller.text
                        : search.query;
                    if (q.trim().isNotEmpty) {
                      search.performSearch(q);
                    }
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Search in All'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
        // Top Result Hero Card (All tab only)
        if (search.filter == SearchFilter.all && results.topResult != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Top Result',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          _buildTopResultCard(
            context,
            results.topResult,
            playback,
            theme,
            colorScheme,
          ),
        ],

        // Songs
        if (results.songs.isNotEmpty &&
            (search.filter == SearchFilter.all ||
                search.filter == SearchFilter.songs)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Songs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...results.songs.map((s) => SongTile(
                song: s,
                contextQueue: results.songs,
              )),
        ],

        // Videos
        if (results.videos.isNotEmpty &&
            (search.filter == SearchFilter.all ||
                search.filter == SearchFilter.videos)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Videos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...results.videos.map((s) => SongTile(
                song: s,
                contextQueue: results.videos,
              )),
        ],

        // Albums
        if (results.albums.isNotEmpty &&
            (search.filter == SearchFilter.all ||
                search.filter == SearchFilter.albums)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'Albums',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(
            height:
                138.0 + 14.0 + MediaQuery.textScalerOf(context).scale(44.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16.0, right: 4.0),
              itemCount: results.albums.length,
              itemBuilder: (ctx, i) {
                final album = results.albums[i];
                return MediaCard(
                  size: 138,
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

        // Artists (`80dp` circular shelf cleanly above scrim)
        if (results.artists.isNotEmpty &&
            (search.filter == SearchFilter.all ||
                search.filter == SearchFilter.artists)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Artists',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(
            height: 80.0 + 12.0 + MediaQuery.textScalerOf(context).scale(24.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16.0, right: 4.0),
              itemCount: results.artists.length,
              itemBuilder: (ctx, i) {
                final artist = results.artists[i];
                return MediaCard(
                  size: 80,
                  title: artist.name,
                  subtitle: artist.subscribers ?? 'Artist',
                  showSubtitle: false,
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
            (search.filter == SearchFilter.all ||
                search.filter == SearchFilter.playlists)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'Playlists',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(
            height:
                138.0 + 14.0 + MediaQuery.textScalerOf(context).scale(44.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16.0, right: 4.0),
              itemCount: results.playlists.length,
              itemBuilder: (ctx, i) {
                final playlist = results.playlists[i];
                return MediaCard(
                  size: 138,
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
    String imageUrl = '';
    bool isCircle = false;
    VoidCallback? onTap;

    if (topResult is Song) {
      title = topResult.title;
      subtitle = topResult.duration > 0
          ? '${topResult.artist} • ${topResult.formattedDuration}'
          : topResult.artist;
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
      final yearStr = topResult.year != null && topResult.year! > 0
          ? ' • ${topResult.year}'
          : '';
      subtitle = 'Album • ${topResult.artist}$yearStr';
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
      subtitle = 'Playlist • ${topResult.author ?? 'YouTube Music'}';
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isCircle ? 28 : 12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl:
                                ThumbnailUtils.upgradeUrl(imageUrl, size: 544),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: colorScheme.surfaceContainerHigh,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: colorScheme.surfaceContainerHigh,
                              child: Icon(
                                isCircle ? Icons.person : Icons.music_note,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Container(
                            color: colorScheme.surfaceContainerHigh,
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
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12.5,
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
      ),
    );
  }
}
