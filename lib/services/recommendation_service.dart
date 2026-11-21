import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../models/song.dart';
import 'database_service.dart';

class UserTasteProfile {
  final Map<String, int> genreWeights;
  final List<String> topGenres;
  final List<String> topArtists;
  final Set<String> listenedSongIds;
  final bool hasHistory;

  const UserTasteProfile({
    required this.genreWeights,
    required this.topGenres,
    required this.topArtists,
    required this.listenedSongIds,
    required this.hasHistory,
  });

  String get dominantGenre => topGenres.isNotEmpty ? topGenres.first : 'Pop';
}

class RecommendationService {
  static final http.Client _httpClient = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

  /// Blacklisted terms indicating compilations, DJ mixes, or multi-hour jukeboxes
  static const List<String> _compilationBlacklist = [
    'jukebox',
    'full album',
    'compilation',
    'non stop',
    'non-stop',
    'nonstop',
    'mashup',
    'dj mix',
    'party mix',
    'megamix',
    'audio jukebox',
    'video jukebox',
    '1 hour',
    '2 hour',
    '3 hour',
    'all songs',
    'top 50',
    'top 100',
    'collection',
    'soundtrack',
    'greatest hits',
    'best songs of',
  ];

  /// Strictly determines if a song is an individual/single track rather than a compilation/jukebox
  static bool isSingleSong(Song song) {
    // Single songs are typically 1.5 to 7 minutes. Anything > 8 min (480s) is a playlist/mix
    if (song.duration > 480 || song.duration < 60) return false;

    final lowerTitle = song.title.toLowerCase();
    for (final kw in _compilationBlacklist) {
      if (lowerTitle.contains(kw)) {
        return false;
      }
    }
    return true;
  }

  /// Categorizes a track into a high-level musical genre
  static String inferGenre(Song song) {
    final text = '${song.title} ${song.artist}'.toLowerCase();

    if (text.contains('lo-fi') ||
        text.contains('lofi') ||
        text.contains('chill') ||
        text.contains('acoustic') ||
        text.contains('ambient') ||
        text.contains('peaceful') ||
        text.contains('sleep')) {
      return 'Chill';
    }
    if (text.contains('love') ||
        text.contains('romantic') ||
        text.contains('romance') ||
        text.contains('dil') ||
        text.contains('pyaar') ||
        text.contains('ishq') ||
        text.contains('heart') ||
        text.contains('humsafar') ||
        text.contains('slow')) {
      return 'Romance';
    }
    if (text.contains('rap') ||
        text.contains('hip hop') ||
        text.contains('hip-hop') ||
        text.contains('trap') ||
        text.contains('drill') ||
        text.contains('flow')) {
      return 'Hip-Hop';
    }
    if (text.contains('party') ||
        text.contains('dance') ||
        text.contains('club') ||
        text.contains('remix') ||
        text.contains('edm') ||
        text.contains('bhangra') ||
        text.contains('dhol')) {
      return 'Party';
    }
    if (text.contains('rock') ||
        text.contains('metal') ||
        text.contains('guitar') ||
        text.contains('punk') ||
        text.contains('band')) {
      return 'Rock';
    }
    if (text.contains('workout') ||
        text.contains('gym') ||
        text.contains('motivation') ||
        text.contains('energy') ||
        text.contains('beast')) {
      return 'Workout';
    }
    if (text.contains('study') ||
        text.contains('focus') ||
        text.contains('instrumental') ||
        text.contains('piano') ||
        text.contains('classical')) {
      return 'Focus';
    }
    if (text.contains('sufi') ||
        text.contains('ghazal') ||
        text.contains('qawwali') ||
        text.contains('folk') ||
        text.contains('indie') ||
        text.contains('unplugged')) {
      return 'Indie';
    }

    return 'Pop';
  }

  /// Builds a taste profile by analyzing user listening history and liked songs
  static UserTasteProfile getUserTasteProfile() {
    final history = DatabaseService.getHistory();
    final liked = DatabaseService.getLikedSongs();

    final allListened = [...history, ...liked];
    final listenedIds = allListened.map((s) => s.id).toSet();

    if (allListened.isEmpty) {
      return const UserTasteProfile(
        genreWeights: {},
        topGenres: [],
        topArtists: [],
        listenedSongIds: {},
        hasHistory: false,
      );
    }

    final genreCounts = <String, int>{};
    final artistCounts = <String, int>{};

    for (int i = 0; i < allListened.length; i++) {
      final song = allListened[i];
      // Recent songs carry higher weight (exponential decay)
      final recencyWeight = i < 5 ? 3 : (i < 15 ? 2 : 1);

      final genre = inferGenre(song);
      genreCounts[genre] = (genreCounts[genre] ?? 0) + recencyWeight;

      final cleanArtist = song.artist.trim();
      if (cleanArtist.isNotEmpty && cleanArtist.toLowerCase() != 'unknown') {
        artistCounts[cleanArtist] = (artistCounts[cleanArtist] ?? 0) + recencyWeight;
      }
    }

    final sortedGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedArtists = artistCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return UserTasteProfile(
      genreWeights: genreCounts,
      topGenres: sortedGenres.map((e) => e.key).toList(),
      topArtists: sortedArtists.take(5).map((e) => e.key).toList(),
      listenedSongIds: listenedIds,
      hasHistory: true,
    );
  }

  /// Fetches recommended songs related to recently listened songs (Item-to-Item Collaborative Filtering)
  static Future<List<Song>> getRelatedTracksForRecentSong(Song recentSong) async {
    final related = <Song>[];

    // Try companion proxy first (super fast and resilient against bot checks)
    try {
      final uri = Uri.parse('https://yt.chocolatemoo53.com/api/v1/videos/${recentSong.id}');
      final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final recs = data['recommendedVideos'] as List<dynamic>?;
        if (recs != null) {
          for (final item in recs.take(15)) {
            final vid = item['videoId'] as String?;
            final title = item['title'] as String?;
            final author = item['author'] as String? ?? 'Unknown';
            final dur = item['lengthSeconds'] as int? ?? 0;
            if (vid == null || title == null) continue;

            final song = Song(
              id: vid,
              title: title,
              artist: author,
              duration: dur,
              thumbnailUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            );
            if (isSingleSong(song)) {
              related.add(song);
            }
          }
        }
      }
    } catch (_) {}

    return related;
  }

  /// Searches targeted single tracks for a given language and genre
  static Future<List<Song>> getGenreTracks(String language, String genre) async {
    final genreQuery = '$language $genre official song 2026';
    try {
      final uri = Uri.parse(
        'https://yt.chocolatemoo53.com/api/v1/search?q=${Uri.encodeComponent(genreQuery)}&type=video',
      );
      final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200) {
        final items = jsonDecode(res.body) as List<dynamic>;
        final list = <Song>[];
        for (final item in items.take(8)) {
          final vid = item['videoId'] as String?;
          final title = item['title'] as String?;
          final author = item['author'] as String? ?? 'Unknown';
          final dur = item['lengthSeconds'] as int? ?? 0;
          if (vid != null && title != null) {
            final s = Song(
              id: vid,
              title: title,
              artist: author,
              duration: dur,
              thumbnailUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            );
            if (isSingleSong(s)) {
              list.add(s);
            }
          }
        }
        return list;
      }
    } catch (_) {}
    return <Song>[];
  }

  /// Searches for trending SINGLE songs for specific languages and mood
  static Future<List<Song>> searchTrendingSinglesForLanguages(
    List<String> languages, {
    String mood = 'All',
  }) async {
    final queries = <String>[];
    for (final lang in languages.take(2)) {
      if (mood == 'All') {
        queries.add('$lang top hits official music video 2026');
        queries.add('$lang trending songs official audio 2026');
      } else {
        queries.add('$lang $mood official song 2026');
      }
    }

    if (queries.isEmpty) {
      queries.add('top hits official music video 2026');
      queries.add('trending songs official audio 2026');
    }

    final queryTasks = queries.take(3).map((q) async {
      try {
        final uri = Uri.parse(
          'https://yt.chocolatemoo53.com/api/v1/search?q=${Uri.encodeComponent(q)}&type=video',
        );
        final res = await _httpClient.get(uri).timeout(const Duration(milliseconds: 1800));
        if (res.statusCode == 200) {
          final items = jsonDecode(res.body) as List<dynamic>;
          final list = <Song>[];
          for (final item in items) {
            final vid = item['videoId'] as String?;
            final title = item['title'] as String?;
            final author = item['author'] as String? ?? 'Unknown';
            final dur = item['lengthSeconds'] as int? ?? 0;
            if (vid == null || title == null) continue;

            final s = Song(
              id: vid,
              title: title,
              artist: author,
              duration: dur,
              thumbnailUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            );
            if (isSingleSong(s)) {
              list.add(s);
            }
          }
          return list.take(10).toList();
        }
      } catch (_) {}

      // Fallback to youtube explode
      try {
        final results = await _ytExplode.search
            .search(q)
            .timeout(const Duration(milliseconds: 1800));
        final list = <Song>[];
        for (final item in results) {
          final s = Song(
            id: item.id.value,
            title: item.title,
            artist: item.author,
            duration: item.duration?.inSeconds ?? 0,
            thumbnailUrl: 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
          );
          if (isSingleSong(s)) {
            list.add(s);
          }
        }
        return list.take(10).toList();
      } catch (_) {
        return <Song>[];
      }
    });

    final taskResults = await Future.wait(queryTasks);
    final merged = <Song>[];
    final maxLen = taskResults.fold<int>(0, (max, l) => l.length > max ? l.length : max);
    for (int i = 0; i < maxLen; i++) {
      for (final list in taskResults) {
        if (i < list.length) merged.add(list[i]);
      }
    }

    final seen = <String>{};
    return merged.where((s) => seen.add(s.id)).toList();
  }

  /// Interleaves trending singles and personalized songs into dedicated slots
  /// ensuring trending songs are always represented and never crowded out.
  static List<Song> blendIntoSlots({
    required List<Song> trendingPool,
    required List<Song> personalizedPool,
  }) {
    final blended = <Song>[];
    final usedIds = <String>{};

    void tryAdd(Song song) {
      if (usedIds.add(song.id)) {
        blended.add(song);
      }
    }

    int trendIdx = 0;
    int persIdx = 0;

    void takeTrending(int count) {
      int taken = 0;
      while (taken < count && trendIdx < trendingPool.length) {
        final s = trendingPool[trendIdx++];
        if (!usedIds.contains(s.id)) {
          tryAdd(s);
          taken++;
        }
      }
    }

    void takePersonalized(int count) {
      int taken = 0;
      while (taken < count && persIdx < personalizedPool.length) {
        final s = personalizedPool[persIdx++];
        if (!usedIds.contains(s.id)) {
          tryAdd(s);
          taken++;
        }
      }
    }

    // Slot 1 & 2: Guaranteed fresh trending singles
    takeTrending(2);

    // Slot 3 & 4: Top personalized genre/artist recommendations
    takePersonalized(2);

    // Slot 5 & 6: Additional viral trending hits
    takeTrending(2);

    // Slot 7 & 8: Deep personalized recommendations
    takePersonalized(2);

    // Remaining slots: Alternating between trending and personalized
    while (trendIdx < trendingPool.length || persIdx < personalizedPool.length) {
      takeTrending(1);
      takePersonalized(1);
    }

    return blended;
  }

  /// Core Recommendation Algorithm: blends trending single songs with genre and artist recommendations
  /// using Slot-Based Interleaving so trending songs are guaranteed in Quick Picks.
  static Future<List<Song>> getPersonalizedQuickPicks({
    List<String>? languages,
    String mood = 'All',
  }) async {
    final activeLanguages = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();

    final tasteProfile = getUserTasteProfile();

    // 1. Parallel Candidate Sourcing: Run Task 1 (Trending Singles), Task 2 (Related Tracks),
    // and Task 3 (User Dominant Genre) concurrently in parallel with Future.wait()
    final tasks = <Future<List<Song>>>[];

    // Task 1: Language trending chart singles
    tasks.add(searchTrendingSinglesForLanguages(activeLanguages, mood: mood));

    // Task 2 & 3: Related tracks and dominant genre tracks if history exists
    if (tasteProfile.hasHistory) {
      final history = DatabaseService.getHistory();
      if (history.isNotEmpty) {
        tasks.add(getRelatedTracksForRecentSong(history.first));
      } else {
        tasks.add(Future.value(<Song>[]));
      }

      final topGenre = tasteProfile.dominantGenre;
      final lang = activeLanguages.isNotEmpty ? activeLanguages.first : 'English';
      tasks.add(getGenreTracks(lang, topGenre));
    } else {
      tasks.add(Future.value(<Song>[]));
      tasks.add(Future.value(<Song>[]));
    }

    final taskResults = await Future.wait(tasks);
    final trendingResults = taskResults[0];
    final relatedResults = taskResults[1];
    final genreResults = taskResults[2];

    // 2. Separate into Trending Pool vs. Personalized Pool
    final trendingPool = <Song>[];
    final seenTrending = <String>{};
    for (final s in trendingResults) {
      if (isSingleSong(s) && seenTrending.add(s.id)) {
        trendingPool.add(s);
      }
    }

    final personalizedCandidates = [...relatedResults, ...genreResults];
    final personalizedScored = <Song, double>{};
    for (final song in personalizedCandidates) {
      if (!isSingleSong(song)) continue;

      double score = 50.0;
      final songGenre = inferGenre(song);

      // Reward matching user's top genres (+30)
      if (tasteProfile.genreWeights.containsKey(songGenre)) {
        score += 30.0;
      }

      // Reward matching user's top artists (+35)
      for (final artist in tasteProfile.topArtists) {
        if (song.artist.toLowerCase().contains(artist.toLowerCase())) {
          score += 35.0;
          break;
        }
      }

      // Fatigue penalty if song is already in listening history (-20)
      if (tasteProfile.listenedSongIds.contains(song.id)) {
        score -= 20.0;
      }

      personalizedScored[song] = score;
    }

    final sortedPersonalized = personalizedScored.keys.toList()
      ..sort((a, b) => personalizedScored[b]!.compareTo(personalizedScored[a]!));

    final personalizedPool = <Song>[];
    final seenPersonalized = <String>{};
    for (final s in sortedPersonalized) {
      if (seenPersonalized.add(s.id)) {
        personalizedPool.add(s);
      }
    }

    // 3. Slot-based interleaved blending
    return blendIntoSlots(
      trendingPool: trendingPool,
      personalizedPool: personalizedPool,
    );
  }
}
