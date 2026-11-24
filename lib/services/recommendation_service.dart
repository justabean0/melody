import '../models/browse_result.dart';
import '../models/search_result.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'innertube_service.dart';

class LanguageConfig {
  final String language;
  final String gl;
  final String hl;
  final List<String> keywords;

  const LanguageConfig({
    required this.language,
    required this.gl,
    required this.hl,
    required this.keywords,
  });
}

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
  static final Map<String, List<MoodGenreItem>> _moodGenreCache = {};
  static final Map<String, List<BrowseMediaItem>> _featuredBrowseCache = {};

  static const Set<String> _indianLanguages = {
    'Hindi',
    'Punjabi',
    'Bengali',
    'Tamil',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Bhojpuri',
    'Marathi',
    'Urdu',
  };

  /// Clears in-memory caches (useful for testing and language changes)
  static void clearCache() {
    _moodGenreCache.clear();
    _featuredBrowseCache.clear();
  }

  /// Maps supported languages to country/language codes and target genre/hub keywords
  static LanguageConfig getLanguageConfig(
    String language, {
    List<String>? allSelectedLanguages,
  }) {
    final hasIndianLangs = allSelectedLanguages?.any(_indianLanguages.contains) ?? true;

    switch (language) {
      case 'Hindi':
        return const LanguageConfig(
          language: 'Hindi',
          gl: 'IN',
          hl: 'en',
          keywords: ['hindi', 'bollywood', 'desi', 'indian pop'],
        );
      case 'Punjabi':
        return const LanguageConfig(
          language: 'Punjabi',
          gl: 'IN',
          hl: 'en',
          keywords: ['punjabi', 'bhangra', 'desi'],
        );
      case 'Tamil':
        return const LanguageConfig(
          language: 'Tamil',
          gl: 'IN',
          hl: 'en',
          keywords: ['tamil', 'kollywood'],
        );
      case 'Telugu':
        return const LanguageConfig(
          language: 'Telugu',
          gl: 'IN',
          hl: 'en',
          keywords: ['telugu', 'tollywood'],
        );
      case 'Bengali':
        return const LanguageConfig(
          language: 'Bengali',
          gl: 'IN',
          hl: 'en',
          keywords: ['bengali', 'bangla'],
        );
      case 'Marathi':
        return const LanguageConfig(
          language: 'Marathi',
          gl: 'IN',
          hl: 'en',
          keywords: ['marathi'],
        );
      case 'Kannada':
        return const LanguageConfig(
          language: 'Kannada',
          gl: 'IN',
          hl: 'en',
          keywords: ['kannada', 'sandalwood'],
        );
      case 'Malayalam':
        return const LanguageConfig(
          language: 'Malayalam',
          gl: 'IN',
          hl: 'en',
          keywords: ['malayalam', 'mollywood'],
        );
      case 'Bhojpuri':
        return const LanguageConfig(
          language: 'Bhojpuri',
          gl: 'IN',
          hl: 'en',
          keywords: ['bhojpuri', 'desi'],
        );
      case 'Korean':
        return const LanguageConfig(
          language: 'Korean',
          gl: 'KR',
          hl: 'en',
          keywords: ['k-pop', 'korean', 'k pop', 'kpop'],
        );
      case 'Japanese':
        return const LanguageConfig(
          language: 'Japanese',
          gl: 'JP',
          hl: 'en',
          keywords: ['j-pop', 'japanese', 'j pop', 'jpop', 'anime'],
        );
      case 'Spanish':
        return const LanguageConfig(
          language: 'Spanish',
          gl: 'MX',
          hl: 'en',
          keywords: ['latin', 'spanish', 'reggaeton', 'latino'],
        );
      case 'French':
        return const LanguageConfig(
          language: 'French',
          gl: 'FR',
          hl: 'en',
          keywords: ['french', 'francais', 'chanson'],
        );
      case 'Arabic':
        return const LanguageConfig(
          language: 'Arabic',
          gl: 'SA',
          hl: 'en',
          keywords: ['arabic', 'khaleeji', 'tarab'],
        );
      case 'Urdu':
        return const LanguageConfig(
          language: 'Urdu',
          gl: 'PK',
          hl: 'en',
          keywords: ['urdu', 'sufi', 'ghazal', 'coke studio'],
        );
      case 'English':
      default:
        return LanguageConfig(
          language: 'English',
          gl: hasIndianLangs ? 'IN' : 'US',
          hl: 'en',
          keywords: const ['pop', 'hits', 'global', 'dance', 'charts'],
        );
    }
  }

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
    // Single songs are typically 1 to 12 minutes. Anything > 12 min (720s) or < 60s (if duration is known) is excluded.
    if (song.duration > 720 || (song.duration > 0 && song.duration < 60)) {
      return false;
    }

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

  /// Caches and returns moods and genres for the specified locale
  static Future<List<MoodGenreItem>> getCachedMoodsAndGenres(String gl, String hl) async {
    final key = '$gl:$hl';
    if (_moodGenreCache.containsKey(key) && _moodGenreCache[key]!.isNotEmpty) {
      return _moodGenreCache[key]!;
    }
    try {
      final items = await InnerTubeService.getMoodsAndGenres(gl: gl, hl: hl);
      if (items.isNotEmpty) {
        _moodGenreCache[key] = items;
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches recommended songs related to recently listened songs
  static Future<List<Song>> getRelatedTracksForRecentSong(Song recentSong) async {
    try {
      final query = '${recentSong.title} ${recentSong.artist}'.trim();
      final res = await InnerTubeService.search(query, filter: SearchFilter.songs);
      return res.songs
          .where((s) => s.id != recentSong.id && isSingleSong(s))
          .take(10)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Searches targeted single tracks for a given language and genre
  static Future<List<Song>> getGenreTracks(String language, String genre) async {
    try {
      final res = await InnerTubeService.search('$language $genre', filter: SearchFilter.songs);
      return res.songs.where(isSingleSong).take(10).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Searches for trending SINGLE songs for specific languages and mood using real InnerTube browse
  static Future<List<Song>> searchTrendingSinglesForLanguages(
    List<String> languages, {
    String mood = 'All',
  }) async {
    final activeLanguages = (languages.isNotEmpty) ? languages : const ['English'];

    // 1. Sync InnerTube locale from primary selected language
    final primaryConfig = getLanguageConfig(
      activeLanguages.first,
      allSelectedLanguages: activeLanguages,
    );
    InnerTubeService.setLocale(gl: primaryConfig.gl, hl: primaryConfig.hl);

    // 2. If a specific mood is requested (not 'All'), attempt to browse that mood hub directly
    if (mood != 'All') {
      try {
        final moodGenres = await getCachedMoodsAndGenres(primaryConfig.gl, primaryConfig.hl);
        final moodMatch = moodGenres.cast<MoodGenreItem?>().firstWhere(
              (m) => m != null && m.title.toLowerCase().contains(mood.toLowerCase()),
              orElse: () => null,
            );
        if (moodMatch != null) {
          final hub = await InnerTubeService.browseMoodOrGenre(
            moodMatch.browseId,
            params: moodMatch.params,
            gl: primaryConfig.gl,
            hl: primaryConfig.hl,
          );
          final moodTracks = <Song>[...hub.songs.where(isSingleSong)];
          if (moodTracks.length < 10 && hub.playlists.isNotEmpty) {
            for (final pl in hub.playlists.take(2)) {
              try {
                final plResult = await InnerTubeService.browsePlaylist(pl.browseId);
                if (plResult != null) {
                  moodTracks.addAll(plResult.songs.where(isSingleSong));
                }
              } catch (_) {}
            }
          }
          if (moodTracks.isNotEmpty) {
            final seen = <String>{};
            return moodTracks.where((s) => seen.add(s.id)).toList();
          }
        }
      } catch (_) {}
    }

    // 3. For each active language (up to 4), fetch and unpack browse items
    final perLanguageFutures = activeLanguages.take(4).map((lang) async {
      final config = getLanguageConfig(lang, allSelectedLanguages: activeLanguages);
      final langCandidates = <Song>[];

      // A. Match language genre hub
      try {
        final moodGenres = await getCachedMoodsAndGenres(config.gl, config.hl);
        MoodGenreItem? matchedItem;
        for (final kw in config.keywords) {
          matchedItem = moodGenres.cast<MoodGenreItem?>().firstWhere(
                (m) => m != null && m.title.toLowerCase().contains(kw.toLowerCase()),
                orElse: () => null,
              );
          if (matchedItem != null) break;
        }

        if (matchedItem != null) {
          final hubResult = await InnerTubeService.browseMoodOrGenre(
            matchedItem.browseId,
            params: matchedItem.params,
            gl: config.gl,
            hl: config.hl,
          );
          langCandidates.addAll(hubResult.songs.where(isSingleSong));

          // Unpack top 1-2 playlists if songs < 10
          if (langCandidates.length < 10 && hubResult.playlists.isNotEmpty) {
            for (final pl in hubResult.playlists.take(2)) {
              try {
                final plResult = await InnerTubeService.browsePlaylist(pl.browseId);
                if (plResult != null) {
                  langCandidates.addAll(plResult.songs.where(isSingleSong));
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // B. Combine with localized charts (unpack top chart playlist if topSongs is sparse)
      try {
        final charts = await InnerTubeService.getCharts(countryCode: config.gl, hl: config.hl);
        langCandidates.addAll(charts.topSongs.where(isSingleSong));

        if (langCandidates.length < 5 && charts.playlists.isNotEmpty) {
          try {
            final plResult = await InnerTubeService.browsePlaylist(charts.playlists.first.browseId);
            if (plResult != null) {
              langCandidates.addAll(plResult.songs.where(isSingleSong));
            }
          } catch (_) {}
        }
      } catch (_) {}

      // C. Fallback: only if hub & charts yielded no songs, search via InnerTube songs
      if (langCandidates.isEmpty) {
        try {
          final searchRes = await InnerTubeService.search(
            '${config.language} top songs',
            filter: SearchFilter.songs,
          );
          langCandidates.addAll(searchRes.songs.where(isSingleSong));
        } catch (_) {}
      }

      // Deduplicate within this language
      final seenLang = <String>{};
      return langCandidates.where((s) => seenLang.add(s.id)).toList();
    });

    final resultsPerLang = await Future.wait(perLanguageFutures);

    // 4. Interleave songs across selected languages
    final merged = <Song>[];
    final maxLen = resultsPerLang.fold<int>(0, (max, l) => l.length > max ? l.length : max);
    for (int i = 0; i < maxLen; i++) {
      for (final list in resultsPerLang) {
        if (i < list.length) {
          merged.add(list[i]);
        }
      }
    }

    final globalSeen = <String>{};
    return merged.where((s) => globalSeen.add(s.id)).toList();
  }

  /// Fetches featured playlists and albums for the Home screen from real InnerTube data
  static Future<List<BrowseMediaItem>> getFeaturedBrowseItems({
    List<String>? languages,
  }) async {
    final activeLangs = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();
    final effectiveLangs = activeLangs.isNotEmpty ? activeLangs : const ['English'];
    final cacheKey = effectiveLangs.join(',');

    if (_featuredBrowseCache.containsKey(cacheKey) &&
        _featuredBrowseCache[cacheKey]!.isNotEmpty) {
      return _featuredBrowseCache[cacheKey]!;
    }

    final items = <BrowseMediaItem>[];
    final seenIds = <String>{};

    void addItem(BrowseMediaItem item) {
      if (item.id.isNotEmpty && item.title.isNotEmpty && seenIds.add(item.id)) {
        items.add(item);
      }
    }

    final primaryConfig = getLanguageConfig(
      effectiveLangs.first,
      allSelectedLanguages: effectiveLangs,
    );

    // 1. Localized charts and explore new releases
    try {
      final chartsFuture = InnerTubeService.getCharts(countryCode: primaryConfig.gl, hl: primaryConfig.hl);
      final exploreFuture = InnerTubeService.getExplore(gl: primaryConfig.gl, hl: primaryConfig.hl);
      final results = await Future.wait([chartsFuture, exploreFuture]);
      final charts = results[0] as ChartsResult;
      final explore = results[1] as ExploreResult;

      for (final pl in charts.playlists) {
        addItem(BrowseMediaItem(
          id: pl.id,
          title: pl.title,
          subtitle: (pl.author != null && pl.author!.isNotEmpty) ? pl.author! : 'Charts',
          thumbnailUrl: pl.thumbnailUrl,
          browseId: pl.browseId,
          type: 'playlist',
        ));
      }

      for (final album in explore.newReleaseAlbums) {
        addItem(BrowseMediaItem(
          id: album.id,
          title: album.title,
          subtitle: album.artist.isNotEmpty ? album.artist : 'New Release',
          thumbnailUrl: album.thumbnailUrl,
          browseId: album.browseId,
          type: 'album',
        ));
      }
    } catch (_) {}

    // 2. Playlists/Albums from language genre hubs
    for (final lang in effectiveLangs.take(3)) {
      final config = getLanguageConfig(lang, allSelectedLanguages: effectiveLangs);
      try {
        final moodGenres = await getCachedMoodsAndGenres(config.gl, config.hl);
        for (final kw in config.keywords) {
          final match = moodGenres.cast<MoodGenreItem?>().firstWhere(
                (m) => m != null && m.title.toLowerCase().contains(kw.toLowerCase()),
                orElse: () => null,
              );
          if (match != null) {
            final hub = await InnerTubeService.browseMoodOrGenre(
              match.browseId,
              params: match.params,
              gl: config.gl,
              hl: config.hl,
            );
            for (final pl in hub.playlists.take(3)) {
              addItem(BrowseMediaItem(
                id: pl.id,
                title: pl.title,
                subtitle: (pl.author != null && pl.author!.isNotEmpty) ? pl.author! : lang,
                thumbnailUrl: pl.thumbnailUrl,
                browseId: pl.browseId,
                type: 'playlist',
              ));
            }
            for (final al in hub.albums.take(3)) {
              addItem(BrowseMediaItem(
                id: al.id,
                title: al.title,
                subtitle: al.artist.isNotEmpty ? al.artist : lang,
                thumbnailUrl: al.thumbnailUrl,
                browseId: al.browseId,
                type: 'album',
              ));
            }
            break;
          }
        }
      } catch (_) {}
    }

    if (items.isNotEmpty) {
      _featuredBrowseCache[cacheKey] = items;
    }
    return items;
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

    // Separate into Trending Pool vs. Personalized Pool
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

    // Slot-based interleaved blending
    return blendIntoSlots(
      trendingPool: trendingPool,
      personalizedPool: personalizedPool,
    );
  }
}
