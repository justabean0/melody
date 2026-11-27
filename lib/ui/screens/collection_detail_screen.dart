import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../models/browse_result.dart';
import '../../models/song.dart';
import '../../providers/playback_provider.dart';
import '../../services/innertube_service.dart';
import '../../widgets/skeleton_loaders.dart';
import '../components/album_card.dart';
import '../components/song_tile.dart';
import 'artist_detail_screen.dart';
import '../../utils/thumbnail_utils.dart';

class CollectionDetailScreen extends StatefulWidget {
  final String browseId;
  final bool isAlbum;
  final String? title;
  final String? subtitle;
  final String? thumbnailUrl;

  const CollectionDetailScreen({
    super.key,
    required this.browseId,
    required this.isAlbum,
    this.title,
    this.subtitle,
    this.thumbnailUrl,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  bool _isLoading = true;
  bool _isResolvingArtist = false;
  String? _errorMessage;
  AlbumBrowseResult? _album;
  PlaylistBrowseResult? _playlist;

  Future<void> _openCollectionArtist() async {
    final artistName = _displaySubtitle.trim();
    if (!widget.isAlbum ||
        artistName.isEmpty ||
        artistName.toLowerCase() == 'unknown artist' ||
        _isResolvingArtist) {
      return;
    }

    final directId = _album?.artistId?.trim();
    if (directId != null && directId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen(
            browseId: directId,
            name: artistName,
          ),
        ),
      );
      return;
    }

    setState(() => _isResolvingArtist = true);
    Artist? resolved;
    try {
      resolved = await InnerTubeService.resolveArtistByName(artistName);
    } catch (_) {
      resolved = null;
    }

    if (!mounted) return;
    setState(() => _isResolvingArtist = false);

    if (resolved != null && resolved.browseId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistDetailScreen(
            browseId: resolved!.browseId,
            name: resolved.name.isNotEmpty ? resolved.name : artistName,
            thumbnailUrl: resolved.thumbnailUrl,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not load artist page for $artistName.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCollection();
  }

  Future<void> _loadCollection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.isAlbum) {
        final res = await InnerTubeService.browseAlbum(widget.browseId);
        if (mounted) {
          if (res != null) {
            setState(() {
              _album = res;
              _isLoading = false;
            });
          } else {
            setState(() {
              _errorMessage = 'Could not load album details';
              _isLoading = false;
            });
          }
        }
      } else {
        final res = await InnerTubeService.browsePlaylist(widget.browseId);
        if (mounted) {
          if (res != null) {
            setState(() {
              _playlist = res;
              _isLoading = false;
            });
          } else {
            setState(() {
              _errorMessage = 'Could not load playlist details';
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading collection: $e';
          _isLoading = false;
        });
      }
    }
  }

  String get _displayTitle {
    if (widget.isAlbum) {
      return _album?.title ?? widget.title ?? 'Album';
    }
    return _playlist?.title ?? widget.title ?? 'Playlist';
  }

  String get _displaySubtitle {
    if (widget.isAlbum) {
      return _album?.artist ?? widget.subtitle ?? 'Unknown Artist';
    }
    return _playlist?.author ?? widget.subtitle ?? 'YouTube Music';
  }

  String get _displayThumbnail {
    if (widget.isAlbum) {
      final url = _album?.thumbnailUrl;
      if (url != null && url.isNotEmpty) return url;
      return widget.thumbnailUrl ?? '';
    }
    final url = _playlist?.thumbnailUrl;
    if (url != null && url.isNotEmpty) return url;
    return widget.thumbnailUrl ?? '';
  }

  List<Song> get _songs {
    if (widget.isAlbum) {
      return _album?.songs ?? const [];
    }
    return _playlist?.songs ?? const [];
  }

  String get _metadataText {
    final count = _songs.length;
    final trackStr = count == 1 ? '1 track' : '$count tracks';
    if (widget.isAlbum) {
      final year = _album?.year;
      if (year != null && year > 0) {
        return '$year • $trackStr';
      }
      return trackStr;
    }
    return trackStr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAlbum ? 'Album' : 'Playlist',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadCollection,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isLoading
              ? const CollectionDetailSkeleton(key: ValueKey('skeleton'))
              : _errorMessage != null && _songs.isEmpty
                  ? _buildErrorView(theme, colorScheme)
                  : _buildContentView(context, theme, colorScheme, playback),
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: _loadCollection,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    PlaybackProvider playback,
  ) {
    final songs = _songs;
    final thumb = _displayThumbnail;
    final otherVersions = _album?.otherVersions ?? const [];
    final description =
        (_album?.description ?? _playlist?.description)?.trim() ?? '';
    final canOpenArtist = widget.isAlbum &&
        _displaySubtitle.trim().isNotEmpty &&
        _displaySubtitle.trim().toLowerCase() != 'unknown artist';

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: () async {
        if (_isLoading) return;
        await _loadCollection();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 16),

          // Artwork Cover
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 190,
                height: 190,
                child: thumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: ThumbnailUtils.upgradeUrl(thumb, size: 1080),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            widget.isAlbum ? Icons.album : Icons.queue_music,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          widget.isAlbum ? Icons.album : Icons.queue_music,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              _displayTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 6),

          // Subtitle / Creator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: canOpenArtist
                ? Center(
                    child: Semantics(
                      button: true,
                      label: 'Open artist $_displaySubtitle',
                      child: InkWell(
                        key: const Key('collection_artist_button'),
                        onTap: _isResolvingArtist ? null : _openCollectionArtist,
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _displaySubtitle,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (_isResolvingArtist)
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Text(
                    _displaySubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),

          const SizedBox(height: 4),

          // Metadata (Year, Track Count)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              _metadataText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withAlpha(200),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons: Play All & Shuffle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: songs.isEmpty
                      ? null
                      : () {
                          playback.playSong(
                            songs.first,
                            contextQueue: songs,
                            startIndex: 0,
                          );
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: songs.isEmpty
                      ? null
                      : () {
                          final shuffled = List<Song>.from(songs)..shuffle();
                          playback.playSong(
                            shuffled.first,
                            contextQueue: shuffled,
                            startIndex: 0,
                          );
                        },
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Tracklist
          if (songs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: Text(
                  'No tracks available',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tracks',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...List.generate(songs.length, (i) {
              final song = songs[i];
              return SongTile(
                song: song,
                contextQueue: songs,
                index: i,
              );
            }),
          ],

          // Other Versions Section (Albums only)
          if (otherVersions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Other Versions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              height: 138.0 + 14.0 + MediaQuery.textScalerOf(context).scale(44.0),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: otherVersions.length,
                itemBuilder: (ctx, i) {
                  final version = otherVersions[i];
                  return MediaCard(
                    title: version.title,
                    subtitle: version.artist,
                    imageUrl: version.thumbnailUrl,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailScreen(
                            browseId: version.browseId,
                            isAlbum: true,
                            title: version.title,
                            subtitle: version.artist,
                            thumbnailUrl: version.thumbnailUrl,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],

          if (description.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'About',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
