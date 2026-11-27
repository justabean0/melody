import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/lyrics.dart';
import '../../providers/playback_provider.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({super.key});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  LyricsData? _trackedLyrics;
  List<GlobalKey> _lineKeys = const [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncLineKeys(LyricsData lyrics) {
    if (!identical(_trackedLyrics, lyrics) ||
        _lineKeys.length != lyrics.syncedLyrics.length) {
      _trackedLyrics = lyrics;
      _lastActiveIndex = -1;
      _lineKeys = List<GlobalKey>.generate(
        lyrics.syncedLyrics.length,
        (_) => GlobalKey(),
      );
    }
  }

  void _scrollToActive(int index, {required bool disableAnimations}) {
    if (index == _lastActiveIndex || index < 0 || index >= _lineKeys.length) {
      return;
    }
    final targetContext = _lineKeys[index].currentContext;
    if (targetContext == null) return;
    _lastActiveIndex = index;

    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.36,
      duration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

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
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 16),
              Text(
                'No lyrics available',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Synced or plain lyrics could not be found for this track.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Plain lyrics
    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 36 + bottomInset),
        child: Text(
          lyrics.plainLyrics ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            height: 1.8,
            color: colorScheme.onSurface.withValues(alpha: 0.88),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Synced lyrics in non-lazy Column so ensureVisible works accurately across any seek jump
    _syncLineKeys(lyrics);
    final activeIndex = playback.activeLyricIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToActive(activeIndex, disableAnimations: disableAnimations);
      }
    });

    final lines = lyrics.syncedLyrics;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(20, 16, 20, 48 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Tap any line to seek',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
              ),
            ),
          ),
          ...List.generate(lines.length, (index) {
            final line = lines[index];
            final isActive = index == activeIndex;
            return KeyedSubtree(
              key: _lineKeys[index],
              child: InkWell(
                onTap: () => playback.seek(Duration(milliseconds: line.timeMs)),
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 8.0,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      style: (theme.textTheme.titleLarge ?? const TextStyle())
                          .copyWith(
                        fontSize: isActive ? 22 : 17,
                        height: 1.35,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.78),
                      ),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
