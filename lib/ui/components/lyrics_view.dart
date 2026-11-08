import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActive(int index) {
    if (index == _lastActiveIndex || !_scrollController.hasClients) return;
    _lastActiveIndex = index;

    // Estimate item height: approx 56px per lyric line
    const itemHeight = 56.0;
    final targetOffset = (index * itemHeight) - 180.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (playback.isLoadingLyrics) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Fetching lyrics...'),
          ],
        ),
      );
    }

    final lyrics = playback.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 64, color: colorScheme.onSurfaceVariant.withAlpha(100)),
            const SizedBox(height: 16),
            Text(
              'No lyrics available',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Plain lyrics
    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Text(
          lyrics.plainLyrics ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            height: 1.8,
            color: colorScheme.onSurface.withAlpha(200),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Synced lyrics
    final activeIndex = playback.activeLyricIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActive(activeIndex);
    });

    final lines = lyrics.syncedLyrics;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      itemCount: lines.length,
      itemBuilder: (ctx, index) {
        final line = lines[index];
        final isActive = index == activeIndex;

        return InkWell(
          onTap: () {
            playback.seek(Duration(milliseconds: line.timeMs));
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
            child: Text(
              line.text,
              style: TextStyle(
                fontSize: isActive ? 22 : 17,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurface.withAlpha(90),
              ),
              textAlign: TextAlign.start,
            ),
          ),
        );
      },
    );
  }
}
