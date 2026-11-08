class LyricLine implements Comparable<LyricLine> {
  final int timeMs;
  final String text;

  LyricLine({required this.timeMs, required this.text});

  @override
  int compareTo(LyricLine other) => timeMs.compareTo(other.timeMs);

  @override
  String toString() => '[$timeMs ms] $text';
}

class LyricsData {
  final List<LyricLine> syncedLyrics;
  final String? plainLyrics;
  final String provider;

  LyricsData({
    this.syncedLyrics = const [],
    this.plainLyrics,
    this.provider = 'LrcLib',
  });

  bool get isSynced => syncedLyrics.isNotEmpty;
  bool get isEmpty => syncedLyrics.isEmpty && (plainLyrics == null || plainLyrics!.trim().isEmpty);

  static final RegExp _lrcRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)');

  /// Parses raw LRC formatted lyrics string into a list of LyricLines
  static List<LyricLine> parseLrc(String rawLrc) {
    final lines = rawLrc.split('\n');
    final List<LyricLine> parsed = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      final match = _lrcRegex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3) ?? '0';
        final millis = int.parse(millisStr.padRight(3, '0').substring(0, 3));

        final totalMs = (minutes * 60 + seconds) * 1000 + millis;
        final text = match.group(4)?.trim() ?? '';

        if (text.isNotEmpty) {
          parsed.add(LyricLine(timeMs: totalMs, text: text));
        }
      }
    }

    parsed.sort();
    return parsed;
  }
}
