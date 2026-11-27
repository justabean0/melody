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
import 'collection_detail_screen.dart';
import '../../utils/thumbnail_utils.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String browseId;
  final String? name;
  final String? thumbnailUrl;

  const ArtistDetailScreen({
    super.key,
    required this.browseId,
    this.name,
    this.thumbnailUrl,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  ArtistBrowseResult? _artist;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await InnerTubeService.browseArtist(widget.browseId);
      if (mounted) {
        if (res != null) {
          setState(() {
            _artist = res;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Could not load artist details';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading artist: $e';
          _isLoading = false;
        });
      }
    }
  }

  String get _displayName => _artist?.name ?? widget.name ?? 'Artist';

  String get _displayThumbnail {
    final url = _artist?.thumbnailUrl;
    if (url != null && url.isNotEmpty) return url;
    return widget.thumbnailUrl ?? '';
  }

  String? get _audienceText {
    final subs = _artist?.subscribers;
    if (subs != null && subs.isNotEmpty) return subs;
    final listeners = _artist?.monthlyListeners;
    if (listeners != null && listeners.isNotEmpty) {
      return listeners.toLowerCase().contains('listener')
          ? listeners
          : '$listeners monthly listeners';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playback = context.read<PlaybackProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadArtist,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isLoading
              ? const ArtistDetailSkeleton(key: ValueKey('skeleton'))
              : _errorMessage != null && (_artist == null || (_artist!.topSongs.isEmpty && _artist!.albums.isEmpty))
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
              onPressed: _loadArtist,
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
    final artist = _artist;
    final topSongs = artist?.topSongs ?? const [];
    final albums = artist?.albums ?? const [];
    final singles = artist?.singles ?? const [];
    final thumb = _displayThumbnail;
    final audience = _audienceText;

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: () async {
        if (_isLoading) return;
        await _loadArtist();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 20),

          // Circular Artist Avatar
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 130,
                height: 130,
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
                            Icons.person,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Artist Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              _displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          if (audience != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                audience,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons: Play Top Songs & Shuffle
          if (topSongs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(150, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () {
                      playback.playSong(
                        topSongs.first,
                        contextQueue: topSongs,
                        startIndex: 0,
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play Songs'),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(130, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () {
                      final shuffled = List<Song>.from(topSongs)..shuffle();
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

          // Top Songs Section
          if (topSongs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Top Songs',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...List.generate(topSongs.length, (i) {
              final song = topSongs[i];
              return SongTile(
                song: song,
                contextQueue: topSongs,
                index: i,
              );
            }),
            const SizedBox(height: 16),
          ],

          // Albums Section
          if (albums.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Albums',
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
                itemCount: albums.length,
                itemBuilder: (ctx, i) {
                  final album = albums[i];
                  return MediaCard(
                    title: album.title,
                    subtitle: album.year != null && album.year! > 0
                        ? '${album.year}'
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
            const SizedBox(height: 16),
          ],

          // Singles & EPs Section
          if (singles.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Singles & EPs',
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
                itemCount: singles.length,
                itemBuilder: (ctx, i) {
                  final single = singles[i];
                  return MediaCard(
                    title: single.title,
                    subtitle: single.year != null && single.year! > 0
                        ? '${single.year}'
                        : 'Single',
                    imageUrl: single.thumbnailUrl,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailScreen(
                            browseId: single.browseId,
                            isAlbum: true,
                            title: single.title,
                            subtitle: single.artist,
                            thumbnailUrl: single.thumbnailUrl,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Bio / Description
          if (artist?.description != null && artist!.description!.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  artist.description!.trim(),
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
