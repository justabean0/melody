import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/browse_result.dart';
import '../models/search_result.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'innertube_service.dart';
import 'log_service.dart';

class LanguageConfig {
  final String language;
  final String gl;
  final String hl;
  final List<String> keywords;
  final bool useCountryCharts;

  const LanguageConfig({
    required this.language,
    required this.gl,
    required this.hl,
    required this.keywords,
    this.useCountryCharts = true,
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
  static final Map<String, DateTime> _featuredBrowseCacheTime = {};
  static const Duration _browseCacheTtl = Duration(minutes: 10);

  static const List<String> _englishExcludedHubTerms = [
    'indian',
    'hindi',
    'desi',
    'bollywood',
    'punjabi',
    'tamil',
    'telugu',
    'bengali',
    'bangla',
    'marathi',
    'kannada',
    'malayalam',
    'bhojpuri',
    'gujarati',
    'haryanvi',
    'k-pop',
    'k pop',
    'kpop',
    'j-pop',
    'j pop',
    'jpop',
    'latin',
    'spanish',
    'reggaeton',
    'french',
    'francais',
    'français',
    'chanson',
    'en français',
    'variété',
    'variete',
    'paroles',
    'clip officiel',
    'vidéo officielle',
    'italian',
    'italiano',
    'german',
    'deutsch',
    'portuguese',
    'português',
    'turkish',
    'türkçe',
    'russian',
    'arabic',
    'urdu',
    'african',
    'afrobeat',
    'carnatic',
    'hindustani',
    'i-pop',
    'tollywood',
    'kollywood',
    'mollywood',
    'sandalwood',
    'cafecito',
    'indo-',
  ];

  static final RegExp _devanagariRegex = RegExp(r'[\u0900-\u097F]');
  static final RegExp _nonLatinScriptRegex = RegExp(
    r'[\u0400-\u04FF\u0600-\u06FF\u0900-\u0DFF\u3040-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]',
  );
  static final RegExp _hindiCueRegex = RegExp(
    r'\b(hindi|bollywood|desi|bhojpuri|haryanvi|t-series|zee music|saiyaara|guzarish|payal|kesariya|satranga|chaleya|tum hi ho|aashiqui|mohabbat|ishq|pyaar|dil|humsafar|sanam|barsaat|tere liye|rabba|zindagi|khuda|arijit|shreya ghoshal|jubin|atif aslam|pritam|neha kakkar|sonu nigam|alka yagnik|udit narayan|armaan malik|darshan raval|mohit chauhan|mohit love|tanishk|b praak|badshah|diljit)\b',
    caseSensitive: false,
  );
  static final RegExp _frenchStrongCueRegex = RegExp(
    r"(?:^|[\s(\[])(?:c'est|j'ai|j'veux|n'est|qu'il|qu'elle|qu'on|l'amour|l'ombre|l'âme|d'un|d'une|aujourd'hui|toujours|jamais|pourquoi|peut-être|dernière|chanson|paroles|clip officiel|vidéo officielle|français|française|cœur|étoile|soleil|maintenant|ensemble)(?:$|[\s)\],.!?:;])",
    caseSensitive: false,
  );
  static final RegExp _frenchAccentRegex = RegExp(r'[àâçéèêëîïôœùûüÿ]', caseSensitive: false);
  static final RegExp _frenchFunctionWordRegex = RegExp(
    r'\b(?:je|tu|nous|vous|mon|ton|son|mes|tes|ses|avec|sans|dans|pour|tout|tous|rien|encore|quand|les|des|une)\b',
    caseSensitive: false,
  );
  static final RegExp _spanishStrongCueRegex = RegExp(
    r'(?:^|[\s(\[])(?:canción|música|corazón|contigo|conmigo|siempre|quien|porque|quiero|ella quiere|quiere beber|una noche|mi gente|baila conmigo|te amo|anuel aa|estoy|para ti|sin ti|te quiero|mi amor|la vida|el amor|una vez|también|video oficial|audio oficial|diablos|neblina|bichote|toco)(?:$|[\s)\],.!?:;])',
    caseSensitive: false,
  );
  static final RegExp _spanishAccentRegex = RegExp(r'[ñ¡¿áéíóú]', caseSensitive: false);
  static final RegExp _spanishFunctionWordRegex = RegExp(
    r'\b(?:que|los|las|por|para|una|del|con|sin|como|pero|más)\b',
    caseSensitive: false,
  );

  /// Detects unmistakable non-English Latin-script tracks (e.g. French or Spanish)
  /// used ONLY to block unseeded chart/hub bleed when English is the entry-gate baseline.
  static bool isLikelyForeignLatinTrack(Song song) {
    final combined = '${song.title} ${song.artist}';
    if (_frenchStrongCueRegex.hasMatch(combined)) return true;
    if (_frenchAccentRegex.hasMatch(combined) &&
        _frenchFunctionWordRegex.hasMatch(combined)) {
      return true;
    }
    if (_spanishStrongCueRegex.hasMatch(combined)) return true;
    if (_spanishAccentRegex.hasMatch(combined) &&
        _spanishFunctionWordRegex.hasMatch(combined)) {
      return true;
    }
    return false;
  }

  /// Normalizes a track title for version deduplication (strips live/acoustic/remix/video tags).
  static String normalizeTrackKey(String title) {
    var normalized = title.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    normalized = normalized.replaceAll(
      RegExp(
        r'\s*[-–|]\s*(?:official\b|lyric\b|audio\b|video\b|live\b|acoustic\b|remix\b|slowed\b|reverb\b|sped up\b|instrumental\b|cover\b|version\b|radio edit\b).*$',
      ),
      ' ',
    );
    normalized = normalized.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  /// Extracts a normalized primary artist key for artist-diversity capping.
  static String primaryArtistKey(String artist) {
    final cleaned = InnerTubeService.cleanArtistText(artist);
    if (cleaned.isEmpty) return '';
    final primary = cleaned
        .split(RegExp(r',|&|\bfeat\.?\b|\bft\.?\b', caseSensitive: false))
        .first
        .trim()
        .toLowerCase();
    if (primary.isEmpty || primary == 'unknown' || primary == 'unknown artist') {
      return '';
    }
    return primary;
  }

  static String _normalizedSongSignature(Song song) {
    final titleKey = normalizeTrackKey(song.title);
    final artistKey = primaryArtistKey(song.artist);
    return artistKey.isNotEmpty ? '$titleKey|$artistKey' : titleKey;
  }

  /// Returns true if a title/text carries regional or non-English markers excluded for [config].
  static bool _isExcludedForConfig(String text, LanguageConfig config) {
    if (config.language != 'English') return false;
    final lower = text.toLowerCase();
    for (final term in _englishExcludedHubTerms) {
      if (lower.contains(term)) return true;
    }
    return false;
  }

  /// Detects likely Hindi/Bollywood songs (Devanagari script or unambiguous Hindi cues).
  static bool isLikelyHindiTrack(Song song) {
    final combined = '${song.title} ${song.artist}';
    if (_devanagariRegex.hasMatch(combined)) return true;
    return _hindiCueRegex.hasMatch(combined);
  }

  /// Checks whether a candidate song is a valid single and matches [config]'s language boundaries.
  static bool _isEligibleTrackForConfig(Song song, LanguageConfig config) {
    if (!isSingleSong(song)) return false;
    if (config.language == 'English') {
      final combined = '${song.title} ${song.artist}';
      if (_isExcludedForConfig(combined, config)) return false;
      if (_nonLatinScriptRegex.hasMatch(combined)) return false;
      if (isLikelyHindiTrack(song)) return false;
      if (isLikelyForeignLatinTrack(song)) return false;
    }
    return true;
  }

  /// Matches a Mood & Genre hub cleanly using exact title matching first, then whole-token matching,
  /// preventing regional pop hubs (e.g. "Indian pop", "K-Pop", "Punjabi Pop") from matching English "pop".
  static MoodGenreItem? matchMoodGenreHub(
    List<MoodGenreItem> moodGenres,
    LanguageConfig config,
  ) {
    final eligible = moodGenres
        .where((m) => !_isExcludedForConfig(m.title, config))
        .toList();

    for (final kw in config.keywords) {
      final lowerKw = kw.toLowerCase();
      final exact = eligible.cast<MoodGenreItem?>().firstWhere(
            (m) => m != null && m.title.trim().toLowerCase() == lowerKw,
            orElse: () => null,
          );
      if (exact != null) return exact;
    }

    for (final kw in config.keywords) {
      final lowerKw = kw.toLowerCase();
      final boundary = RegExp('(^|[^a-z0-9])${RegExp.escape(lowerKw)}([^a-z0-9]|\$)');
      final partial = eligible.cast<MoodGenreItem?>().firstWhere(
            (m) => m != null && boundary.hasMatch(m.title.toLowerCase()),
            orElse: () => null,
          );
      if (partial != null) return partial;
    }

    return null;
  }

  /// Clears in-memory caches (useful for testing and language changes)
  static void clearCache() {
    _moodGenreCache.clear();
    _featuredBrowseCache.clear();
    _featuredBrowseCacheTime.clear();
  }

  /// Maps supported languages to country/language codes and target genre/hub keywords
  static LanguageConfig getLanguageConfig(
    String language, {
    List<String>? allSelectedLanguages,
  }) {
    switch (language) {
      case 'Hindi':
        return const LanguageConfig(
          language: 'Hindi',
          gl: 'IN',
          hl: 'en',
          keywords: ['hindi', 'bollywood', 'desi', 'indian pop'],
          useCountryCharts: true,
        );
      case 'Punjabi':
        return const LanguageConfig(
          language: 'Punjabi',
          gl: 'IN',
          hl: 'en',
          keywords: ['punjabi', 'bhangra', 'desi'],
          useCountryCharts: false,
        );
      case 'Tamil':
        return const LanguageConfig(
          language: 'Tamil',
          gl: 'IN',
          hl: 'en',
          keywords: ['tamil', 'kollywood'],
          useCountryCharts: false,
        );
      case 'Telugu':
        return const LanguageConfig(
          language: 'Telugu',
          gl: 'IN',
          hl: 'en',
          keywords: ['telugu', 'tollywood'],
          useCountryCharts: false,
        );
      case 'Bengali':
        return const LanguageConfig(
          language: 'Bengali',
          gl: 'IN',
          hl: 'en',
          keywords: ['bengali', 'bangla'],
          useCountryCharts: false,
        );
      case 'Marathi':
        return const LanguageConfig(
          language: 'Marathi',
          gl: 'IN',
          hl: 'en',
          keywords: ['marathi'],
          useCountryCharts: false,
        );
      case 'Kannada':
        return const LanguageConfig(
          language: 'Kannada',
          gl: 'IN',
          hl: 'en',
          keywords: ['kannada', 'sandalwood'],
          useCountryCharts: false,
        );
      case 'Malayalam':
        return const LanguageConfig(
          language: 'Malayalam',
          gl: 'IN',
          hl: 'en',
          keywords: ['malayalam', 'mollywood'],
          useCountryCharts: false,
        );
      case 'Bhojpuri':
        return const LanguageConfig(
          language: 'Bhojpuri',
          gl: 'IN',
          hl: 'en',
          keywords: ['bhojpuri', 'desi'],
          useCountryCharts: false,
        );
      case 'Korean':
        return const LanguageConfig(
          language: 'Korean',
          gl: 'KR',
          hl: 'en',
          keywords: ['k-pop', 'korean', 'k pop', 'kpop'],
          useCountryCharts: true,
        );
      case 'Japanese':
        return const LanguageConfig(
          language: 'Japanese',
          gl: 'JP',
          hl: 'en',
          keywords: ['j-pop', 'japanese', 'j pop', 'jpop', 'anime'],
          useCountryCharts: true,
        );
      case 'Spanish':
        return const LanguageConfig(
          language: 'Spanish',
          gl: 'MX',
          hl: 'en',
          keywords: ['latin', 'spanish', 'reggaeton', 'latino'],
          useCountryCharts: true,
        );
      case 'French':
        return const LanguageConfig(
          language: 'French',
          gl: 'FR',
          hl: 'en',
          keywords: ['french', 'francais', 'chanson'],
          useCountryCharts: true,
        );
      case 'Arabic':
        return const LanguageConfig(
          language: 'Arabic',
          gl: 'SA',
          hl: 'en',
          keywords: ['arabic', 'khaleeji', 'tarab'],
          useCountryCharts: true,
        );
      case 'Urdu':
        return const LanguageConfig(
          language: 'Urdu',
          gl: 'PK',
          hl: 'en',
          keywords: ['urdu', 'sufi', 'ghazal', 'coke studio'],
          useCountryCharts: true,
        );
      case 'English':
      default:
        return const LanguageConfig(
          language: 'English',
          gl: 'US',
          hl: 'en',
          keywords: ['pop', 'hits', 'dance', 'rock', 'hip-hop'],
          useCountryCharts: true,
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

  /// Builds a taste profile by analyzing user listening history and liked songs.
  /// Excludes podcast episodes so music genre/artist weights reflect musical taste.
  static UserTasteProfile getUserTasteProfile() {
    final history = DatabaseService.getHistory().where((s) => !s.isPodcast).toList();
    final liked = DatabaseService.getLikedSongs().where((s) => !s.isPodcast).toList();

    final seenIds = <String>{};
    final allListened = <Song>[];
    for (final s in [...history, ...liked]) {
      if (seenIds.add(s.id)) {
        allListened.add(s);
      }
    }
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

      final cleanArtist = InnerTubeService.cleanArtistText(song.artist);
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

  /// Fetches similar/related songs for [recentSong] via InnerTube `next` (`RDAMVM`)
  /// and `MPTRt_` related-artist tabs, falling back to artist/genre discovery
  /// search if radio endpoints yield nothing.
  static Future<List<Song>> getRelatedTracksForRecentSong(
    Song recentSong, {
    String? gl,
    String? hl,
  }) async {
    final seedNormalized = normalizeTrackKey(recentSong.title);
    final seedArtist = primaryArtistKey(recentSong.artist);
    final related = <Song>[];
    final seenIds = <String>{recentSong.id};
    final seenNormalized = <String>{};
    if (seedNormalized.isNotEmpty) {
      seenNormalized.add(seedArtist.isNotEmpty ? '$seedNormalized|$seedArtist' : seedNormalized);
    }

    void collect(Iterable<Song> candidates) {
      for (final s in candidates) {
        if (s.isPodcast || !isSingleSong(s)) continue;
        final sNorm = normalizeTrackKey(s.title);
        if (seedNormalized.isNotEmpty && sNorm == seedNormalized) continue;
        final sig = _normalizedSongSignature(s);
        if (!seenIds.add(s.id)) continue;
        if (sNorm.isNotEmpty && !seenNormalized.add(sig)) continue;
        related.add(s);
      }
    }

    try {
      final mix = await InnerTubeService.getWatchNextMix(
        recentSong.id,
        gl: gl,
        hl: hl,
      );
      if (mix.relatedBrowseId != null && mix.relatedBrowseId!.isNotEmpty) {
        final tabRelated = await InnerTubeService.browseRelatedTracks(
          mix.relatedBrowseId!,
          gl: gl,
          hl: hl,
        );
        collect(tabRelated);
      }
      collect(mix.songs);
    } catch (_) {}

    if (related.length < 6) {
      try {
        final cleanArtist = InnerTubeService.cleanArtistText(recentSong.artist);
        final genre = inferGenre(recentSong);
        final query = (cleanArtist.isNotEmpty &&
                cleanArtist.toLowerCase() != 'unknown' &&
                cleanArtist.toLowerCase() != 'unknown artist')
            ? '$cleanArtist ${genre != 'Pop' ? genre : 'similar'} songs'.trim()
            : '$genre hits songs';
        final res = await InnerTubeService.search(
          query,
          filter: SearchFilter.songs,
          gl: gl,
          hl: hl,
        );
        collect(res.songs);
      } catch (_) {}
    }

    return related.take(20).toList();
  }

  /// Searches targeted single tracks for a given language and genre
  static Future<List<Song>> getGenreTracks(
    String language,
    String genre, {
    String? gl,
    String? hl,
  }) async {
    try {
      final config = getLanguageConfig(language);
      final res = await InnerTubeService.search(
        '$language $genre',
        filter: SearchFilter.songs,
        gl: gl ?? config.gl,
        hl: hl ?? config.hl,
      );
      return res.songs
          .where((s) => _isEligibleTrackForConfig(s, config))
          .take(16)
          .toList();
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

    LogService.info(
      'searchTrendingSinglesForLanguages activeLanguages=$activeLanguages mood=$mood primaryGl=${primaryConfig.gl}',
      tag: 'Feed',
    );

    // 2. If a specific mood is requested (not 'All'), query and interleave across up to 3 active languages
    if (mood != 'All') {
      final perLangMoodFutures = activeLanguages.take(3).map((lang) async {
        final config = getLanguageConfig(lang, allSelectedLanguages: activeLanguages);
        final langMoodTracks = <Song>[];
        String matchedHubTitle = 'none';
        String searchQueryUsed = 'none';
        int searchCount = 0;

        if (config.useCountryCharts) {
          try {
            final moodGenres = await getCachedMoodsAndGenres(config.gl, config.hl);
            final moodMatch = moodGenres.cast<MoodGenreItem?>().firstWhere(
                  (m) => m != null && m.title.toLowerCase().contains(mood.toLowerCase()),
                  orElse: () => null,
                );
            if (moodMatch != null) {
              matchedHubTitle = moodMatch.title;
              final hub = await InnerTubeService.browseMoodOrGenre(
                moodMatch.browseId,
                params: moodMatch.params,
                gl: config.gl,
                hl: config.hl,
              );
              langMoodTracks.addAll(
                hub.songs.where((s) => _isEligibleTrackForConfig(s, config)),
              );

              // Only unpack generic mood hub playlists for Hindi (since YouTube Music's mood playlists
              // are heavily IP-geolocated to Bollywood/Indian mixes on Indian IPs regardless of gl).
              if (config.language == 'Hindi' &&
                  langMoodTracks.length < 10 &&
                  hub.playlists.isNotEmpty) {
                for (final pl in hub.playlists.take(2)) {
                  try {
                    final plResult = await InnerTubeService.browsePlaylist(
                      pl.browseId,
                      gl: config.gl,
                      hl: config.hl,
                    );
                    if (plResult != null) {
                      langMoodTracks.addAll(
                        plResult.songs.where((s) => _isEligibleTrackForConfig(s, config)),
                      );
                    }
                  } catch (_) {}
                }
              }
            }
          } catch (_) {}
        }

        // Fallback: search for language + mood songs if hub yielded fewer than 10 tracks
        if (langMoodTracks.length < 10) {
          try {
            searchQueryUsed = '${config.language} $mood songs';
            final searchRes = await InnerTubeService.search(
              searchQueryUsed,
              filter: SearchFilter.songs,
              gl: config.gl,
              hl: config.hl,
            );
            final eligible = searchRes.songs
                .where((s) => _isEligibleTrackForConfig(s, config))
                .toList();
            searchCount = eligible.length;
            langMoodTracks.addAll(eligible);
          } catch (_) {}
        }

        final seen = <String>{};
        final uniqueLangMood = langMoodTracks.where((s) => seen.add(s.id)).toList();
        final top2 = uniqueLangMood.take(2).map((s) => '"${s.title}" (${s.id})').join(', ');
        LogService.info(
          'lang=${config.language} gl=${config.gl} useCountryCharts=${config.useCountryCharts} mood=$mood hub="$matchedHubTitle" charts=0 search="$searchQueryUsed":$searchCount total=${uniqueLangMood.length} top2=[$top2]',
          tag: 'Feed',
        );
        return uniqueLangMood;
      });

      final perLangMoodResults = await Future.wait(perLangMoodFutures);

      final mergedMoodTracks = <Song>[];
      final maxMoodLen = perLangMoodResults.fold<int>(0, (m, l) => l.length > m ? l.length : m);
      for (int i = 0; i < maxMoodLen; i++) {
        for (final list in perLangMoodResults) {
          if (i < list.length) {
            mergedMoodTracks.add(list[i]);
          }
        }
      }

      final seenMood = <String>{};
      final uniqueMoodTracks = mergedMoodTracks.where((s) => seenMood.add(s.id)).toList();
      if (uniqueMoodTracks.isNotEmpty) {
        return uniqueMoodTracks;
      }
    }

    // 3. For each active language (up to 4), fetch and unpack browse items
    final perLanguageFutures = activeLanguages.take(4).map((lang) async {
      final config = getLanguageConfig(lang, allSelectedLanguages: activeLanguages);
      final langCandidates = <Song>[];
      String matchedHubTitle = 'none';
      int chartCount = 0;
      String searchQueryUsed = 'none';
      int searchCount = 0;

      // A. Match language genre hub
      try {
        final moodGenres = await getCachedMoodsAndGenres(config.gl, config.hl);
        final matchedItem = matchMoodGenreHub(moodGenres, config);

        if (matchedItem != null) {
          matchedHubTitle = matchedItem.title;
          final hubResult = await InnerTubeService.browseMoodOrGenre(
            matchedItem.browseId,
            params: matchedItem.params,
            gl: config.gl,
            hl: config.hl,
          );
          langCandidates.addAll(
            hubResult.songs.where((s) => _isEligibleTrackForConfig(s, config)),
          );

          // Unpack top 1-2 playlists if songs < 16
          if (langCandidates.length < 16 && hubResult.playlists.isNotEmpty) {
            final cleanPlaylists = hubResult.playlists
                .where((pl) => !_isExcludedForConfig(pl.title, config))
                .take(2);
            for (final pl in cleanPlaylists) {
              try {
                final plResult = await InnerTubeService.browsePlaylist(
                  pl.browseId,
                  gl: config.gl,
                  hl: config.hl,
                );
                if (plResult != null) {
                  langCandidates.addAll(
                    plResult.songs.where((s) => _isEligibleTrackForConfig(s, config)),
                  );
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // B. Combine with localized charts (ONLY for languages whose country charts match)
      if (config.useCountryCharts) {
        try {
          final charts = await InnerTubeService.getCharts(countryCode: config.gl, hl: config.hl);
          final chartSongs = charts.topSongs
              .where((s) => _isEligibleTrackForConfig(s, config))
              .toList();
          chartCount = chartSongs.length;
          langCandidates.addAll(chartSongs);

          if (langCandidates.length < 10 && charts.playlists.isNotEmpty) {
            final cleanChartPlaylists = charts.playlists
                .where((pl) => !_isExcludedForConfig(pl.title, config))
                .toList();
            if (cleanChartPlaylists.isNotEmpty) {
              try {
                final plResult = await InnerTubeService.browsePlaylist(
                  cleanChartPlaylists.first.browseId,
                  gl: config.gl,
                  hl: config.hl,
                );
                if (plResult != null) {
                  final unpacked = plResult.songs
                      .where((s) => _isEligibleTrackForConfig(s, config))
                      .toList();
                  chartCount += unpacked.length;
                  langCandidates.addAll(unpacked);
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      // C. Fallback: if candidates < 16 (especially regional Indian languages or sparse/filtered hubs)
      if (langCandidates.length < 16) {
        try {
          searchQueryUsed = config.language == 'English'
              ? 'top english pop songs'
              : '${config.language} top songs';
          final searchRes = await InnerTubeService.search(
            searchQueryUsed,
            filter: SearchFilter.songs,
            gl: config.gl,
            hl: config.hl,
          );
          final eligible = searchRes.songs
              .where((s) => _isEligibleTrackForConfig(s, config))
              .toList();
          searchCount = eligible.length;
          langCandidates.addAll(eligible);
        } catch (_) {}
      }

      // Deduplicate within this language
      final seenLang = <String>{};
      final uniqueLangSongs = langCandidates.where((s) => seenLang.add(s.id)).toList();
      final top2 = uniqueLangSongs.take(2).map((s) => '"${s.title}" (${s.id})').join(', ');
      LogService.info(
        'lang=${config.language} gl=${config.gl} useCountryCharts=${config.useCountryCharts} mood=$mood hub="$matchedHubTitle" charts=$chartCount search="$searchQueryUsed":$searchCount total=${uniqueLangSongs.length} top2=[$top2]',
        tag: 'Feed',
      );
      return uniqueLangSongs;
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

  /// Fetches featured playlists and albums for the Home screen from real InnerTube data,
  /// backed by both in-memory and disk cache so fresh launches render immediately.
  static Future<List<BrowseMediaItem>> getFeaturedBrowseItems({
    List<String>? languages,
    bool forceRefresh = false,
  }) async {
    final activeLangs = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();
    final effectiveLangs = activeLangs.isNotEmpty ? activeLangs : const ['English'];
    final cacheKey = effectiveLangs.join(',');
    final diskKey = 'lang:$cacheKey';

    if (!forceRefresh) {
      final memTime = _featuredBrowseCacheTime[cacheKey];
      final memFresh =
          memTime != null && DateTime.now().difference(memTime) < _browseCacheTtl;
      if (memFresh &&
          _featuredBrowseCache.containsKey(cacheKey) &&
          _featuredBrowseCache[cacheKey]!.isNotEmpty) {
        return _featuredBrowseCache[cacheKey]!;
      }

      final diskTime = DatabaseService.getCachedBrowseTimestamp(diskKey);
      final diskFresh =
          diskTime != null && DateTime.now().difference(diskTime) < _browseCacheTtl;
      final diskItems = DatabaseService.getCachedBrowseItems(diskKey);
      if (diskFresh && diskItems.isNotEmpty) {
        _featuredBrowseCache[cacheKey] = diskItems;
        _featuredBrowseCacheTime[cacheKey] = diskTime;
        return diskItems;
      }
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

    // 1. Localized charts and explore new releases (general top media)
    // Only query when primaryConfig.useCountryCharts is true (national-majority languages)
    // so regional languages sharing gl: 'IN' (e.g. Bengali, Tamil) never get Hindi charts injected.
    final generalCards = <BrowseMediaItem>[];
    if (primaryConfig.useCountryCharts) {
      try {
        final chartsFuture = InnerTubeService.getCharts(countryCode: primaryConfig.gl, hl: primaryConfig.hl);
        // FEmusic_explore ignores gl on Indian IPs and injects Indian releases, so only query it when gl == 'IN'.
        final exploreFuture = primaryConfig.gl == 'IN'
            ? InnerTubeService.getExplore(gl: primaryConfig.gl, hl: primaryConfig.hl)
            : Future.value(const ExploreResult());
        final results = await Future.wait([chartsFuture, exploreFuture]);
        final charts = results[0] as ChartsResult;
        final explore = results[1] as ExploreResult;

        for (final pl in charts.playlists) {
          if (_isExcludedForConfig(pl.title, primaryConfig)) continue;
          generalCards.add(BrowseMediaItem(
            id: pl.id,
            title: pl.title,
            subtitle: (pl.author != null && pl.author!.isNotEmpty) ? pl.author! : 'Charts',
            thumbnailUrl: pl.thumbnailUrl,
            browseId: pl.browseId,
            type: 'playlist',
          ));
        }

        for (final album in explore.newReleaseAlbums) {
          if (_isExcludedForConfig('${album.title} ${album.artist}', primaryConfig)) continue;
          generalCards.add(BrowseMediaItem(
            id: album.id,
            title: album.title,
            subtitle: album.artist.isNotEmpty ? album.artist : 'New Release',
            thumbnailUrl: album.thumbnailUrl,
            browseId: album.browseId,
            type: 'album',
          ));
        }
      } catch (_) {}
    }

    // 2. Playlists/Albums per selected language (up to 3 in parallel)
    final perLanguageFutures = effectiveLangs.take(3).map((lang) async {
      final config = getLanguageConfig(lang, allSelectedLanguages: effectiveLangs);
      final langCards = <BrowseMediaItem>[];

      // A. Try language genre hub
      try {
        final moodGenres = await getCachedMoodsAndGenres(config.gl, config.hl);
        final match = matchMoodGenreHub(moodGenres, config);

        if (match != null) {
          final hub = await InnerTubeService.browseMoodOrGenre(
            match.browseId,
            params: match.params,
            gl: config.gl,
            hl: config.hl,
          );
          for (final pl in hub.playlists.where((p) => !_isExcludedForConfig(p.title, config)).take(3)) {
            langCards.add(BrowseMediaItem(
              id: pl.id,
              title: pl.title,
              subtitle: (pl.author != null && pl.author!.isNotEmpty) ? pl.author! : lang,
              thumbnailUrl: pl.thumbnailUrl,
              browseId: pl.browseId,
              type: 'playlist',
            ));
          }
          for (final al in hub.albums.where((a) => !_isExcludedForConfig('${a.title} ${a.artist}', config)).take(3)) {
            langCards.add(BrowseMediaItem(
              id: al.id,
              title: al.title,
              subtitle: al.artist.isNotEmpty ? al.artist : lang,
              thumbnailUrl: al.thumbnailUrl,
              browseId: al.browseId,
              type: 'album',
            ));
          }
        }
      } catch (_) {}

      // B. Fallback: if no matching hub (e.g. Bengali) or sparse items, search for playlist hits
      if (langCards.isEmpty) {
        try {
          final searchRes = await InnerTubeService.search(
            '${config.language} hits playlist',
            filter: SearchFilter.playlists,
            gl: config.gl,
            hl: config.hl,
          );
          for (final pl in searchRes.playlists.where((p) => !_isExcludedForConfig(p.title, config)).take(4)) {
            langCards.add(BrowseMediaItem(
              id: pl.id,
              title: pl.title,
              subtitle: (pl.author != null && pl.author!.isNotEmpty) ? pl.author! : lang,
              thumbnailUrl: pl.thumbnailUrl,
              browseId: pl.browseId,
              type: 'playlist',
            ));
          }
        } catch (_) {}
      }

      return langCards;
    });

    final perLanguageItems = await Future.wait(perLanguageFutures);

    // 3. Assemble and interleave cards across languages (round-robin)
    // Add first 1-2 top general cards (e.g., chart playlist + top new release album)
    if (generalCards.isNotEmpty) {
      addItem(generalCards[0]);
    }
    if (generalCards.length > 1) {
      addItem(generalCards[1]);
    }

    // Interleave language-specific cards so every selected language is well-represented
    final maxPerLang = perLanguageItems.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxPerLang; i++) {
      for (final list in perLanguageItems) {
        if (i < list.length) {
          addItem(list[i]);
        }
      }
    }

    // Append any remaining general chart/release cards
    for (int i = 2; i < generalCards.length; i++) {
      addItem(generalCards[i]);
    }

    if (items.isNotEmpty) {
      _featuredBrowseCache[cacheKey] = items;
      _featuredBrowseCacheTime[cacheKey] = DateTime.now();
      await DatabaseService.saveCachedBrowseItems(diskKey, items);
      return items;
    }

    final fallbackDisk = DatabaseService.getCachedBrowseItems(diskKey);
    if (fallbackDisk.isNotEmpty) {
      return fallbackDisk;
    }
    return items;
  }

  static ({List<Song> songs, Map<String, String> slotOrigins}) _blendIntoSlotsWithOrigins({
    required List<Song> trendingPool,
    required List<Song> personalizedPool,
    required Set<String> task2HistoryIds,
    required Set<String> task3GenreIds,
  }) {
    final blended = <Song>[];
    final slotOrigins = <String, String>{};
    final usedIds = <String>{};

    void tryAdd(Song song, String origin) {
      if (usedIds.add(song.id)) {
        blended.add(song);
        slotOrigins[song.id] = origin;
      }
    }

    int trendIdx = 0;
    int persIdx = 0;

    void takeTrending(int count) {
      int taken = 0;
      while (taken < count && trendIdx < trendingPool.length) {
        final s = trendingPool[trendIdx++];
        if (!usedIds.contains(s.id)) {
          tryAdd(s, 'trending');
          taken++;
        }
      }
    }

    void takePersonalized(int count) {
      int taken = 0;
      while (taken < count && persIdx < personalizedPool.length) {
        final s = personalizedPool[persIdx++];
        if (!usedIds.contains(s.id)) {
          final origin = task3GenreIds.contains(s.id)
              ? 'personalized:Task3-genre'
              : (task2HistoryIds.contains(s.id)
                  ? 'personalized:Task2-history'
                  : 'personalized');
          tryAdd(s, origin);
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

    return (songs: blended, slotOrigins: slotOrigins);
  }

  /// Interleaves trending singles and personalized songs into dedicated slots
  /// ensuring trending songs are always represented and never crowded out.
  static List<Song> blendIntoSlots({
    required List<Song> trendingPool,
    required List<Song> personalizedPool,
  }) {
    return _blendIntoSlotsWithOrigins(
      trendingPool: trendingPool,
      personalizedPool: personalizedPool,
      task2HistoryIds: const {},
      task3GenreIds: const {},
    ).songs;
  }

  /// Selects up to [maxSeeds] diverse seed tracks from recent plays and liked songs.
  /// Allows any language the user explicitly played or liked (earned taste).
  static List<Song> _selectDiverseTasteSeeds({
    required List<Song> history,
    required List<Song> liked,
    Song? activeSong,
    int maxSeeds = 2,
  }) {
    final seeds = <Song>[];
    final usedArtists = <String>{};
    final usedIds = <String>{};

    // Interleave latest plays and latest likes so likes immediately influence Quick Picks
    final combined = <Song>[];
    final maxLen = history.length > liked.length ? history.length : liked.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < history.length) combined.add(history[i]);
      if (i < liked.length) combined.add(liked[i]);
    }

    for (final s in combined) {
      if (s.isPodcast) continue;
      if (!usedIds.add(s.id)) continue;
      final artistKey = primaryArtistKey(s.artist);
      if (artistKey.isNotEmpty && usedArtists.contains(artistKey) && seeds.isNotEmpty) {
        continue;
      }
      if (artistKey.isNotEmpty) usedArtists.add(artistKey);
      seeds.add(s);
      if (seeds.length >= maxSeeds) break;
    }

    if (seeds.isEmpty && activeSong != null && !activeSong.isPodcast) {
      seeds.add(activeSong);
    }

    return seeds;
  }

  /// Applies version deduplication, active-track suppression, and per-artist capping
  /// (`maxPerArtist`, default 2) while preferring broad artist variety in top slots.
  @visibleForTesting
  static List<Song> diversifyAndCapQuickPicks(
    List<Song> candidates, {
    Song? activeSong,
    int maxPerArtist = 2,
    int maxCount = 32,
  }) {
    final activeId = activeSong?.id;
    final activeNormTitle = activeSong != null ? normalizeTrackKey(activeSong.title) : '';
    final activeArtist = activeSong != null ? primaryArtistKey(activeSong.artist) : '';

    final seenIds = <String>{};
    final seenSignatures = <String>{};
    final artistCounts = <String, int>{};
    final primaryPass = <Song>[];
    final overflowPass = <Song>[];

    for (final raw in candidates) {
      if (raw.isPodcast || !isSingleSong(raw)) continue;
      if (activeId != null && raw.id == activeId) continue;

      final normTitle = normalizeTrackKey(raw.title);
      final artistKey = primaryArtistKey(raw.artist);

      // Prevent revisited/live/remix/acoustic duplicates of the active playing song
      if (activeNormTitle.isNotEmpty &&
          normTitle == activeNormTitle &&
          (activeArtist.isEmpty || artistKey.isEmpty || artistKey == activeArtist)) {
        continue;
      }

      if (!seenIds.add(raw.id)) continue;
      final signature = artistKey.isNotEmpty ? '$normTitle|$artistKey' : normTitle;
      if (normTitle.isNotEmpty && !seenSignatures.add(signature)) continue;

      if (artistKey.isEmpty) {
        primaryPass.add(raw);
        continue;
      }

      final currentCount = artistCounts[artistKey] ?? 0;
      if (currentCount >= maxPerArtist) continue;
      artistCounts[artistKey] = currentCount + 1;

      if (currentCount == 0) {
        primaryPass.add(raw);
      } else {
        overflowPass.add(raw);
      }
    }

    final result = <Song>[...primaryPass, ...overflowPass];
    return result.take(maxCount).toList();
  }

  /// Core Recommendation Algorithm: blends selected-language discovery with similar-song
  /// seeds from recent plays & likes, preserving earned user taste across languages
  /// while capping tracks per artist and deduplicating versions.
  static Future<List<Song>> getPersonalizedQuickPicks({
    List<String>? languages,
    String mood = 'All',
    Song? activeSong,
  }) async {
    final activeLanguages = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();
    final primaryConfig = getLanguageConfig(
      activeLanguages.first,
      allSelectedLanguages: activeLanguages,
    );

    final tasteProfile = getUserTasteProfile();
    final history = DatabaseService.getHistory();
    final liked = DatabaseService.getLikedSongs();
    final seeds = tasteProfile.hasHistory
        ? _selectDiverseTasteSeeds(
            history: history,
            liked: liked,
            activeSong: activeSong,
            maxSeeds: 2,
          )
        : const <Song>[];

    final tasks = <Future<List<Song>>>[];

    // Task 1: Baseline selected-language trending singles (strict entry-gate)
    tasks.add(searchTrendingSinglesForLanguages(activeLanguages, mood: mood));

    // Task 2: Related/radio tracks seeded from user's plays & likes (earned taste allowed!)
    if (seeds.isNotEmpty) {
      tasks.add(
        Future.wait(
          seeds.map(
            (seed) => getRelatedTracksForRecentSong(
              seed,
              gl: primaryConfig.gl,
              hl: primaryConfig.hl,
            ),
          ),
        ).then((lists) {
          final interleaved = <Song>[];
          final maxLen = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
          for (int i = 0; i < maxLen; i++) {
            for (final l in lists) {
              if (i < l.length) interleaved.add(l[i]);
            }
          }
          return interleaved;
        }),
      );

      final topGenre = tasteProfile.dominantGenre;
      final targetLangs = activeLanguages.take(3).toList();
      final genreTasks = targetLangs.map((l) {
        final config = getLanguageConfig(l, allSelectedLanguages: activeLanguages);
        return getGenreTracks(l, topGenre, gl: config.gl, hl: config.hl);
      });
      tasks.add(Future.wait(genreTasks).then((genreResultsList) {
        final mergedGenreTracks = <Song>[];
        final maxG = genreResultsList.fold<int>(0, (m, l) => l.length > m ? l.length : m);
        for (int i = 0; i < maxG; i++) {
          for (final list in genreResultsList) {
            if (i < list.length) {
              mergedGenreTracks.add(list[i]);
            }
          }
        }
        return mergedGenreTracks;
      }));
    } else {
      tasks.add(Future.value(<Song>[]));
      tasks.add(Future.value(<Song>[]));
    }

    final taskResults = await Future.wait(tasks);
    final trendingResults = taskResults[0];
    final relatedResults = taskResults[1];
    final genreResults = taskResults[2];

    final trendingPool = <Song>[];
    final seenTrending = <String>{};
    for (final s in trendingResults) {
      if (!s.isPodcast && isSingleSong(s) && seenTrending.add(s.id)) {
        trendingPool.add(s);
      }
    }

    final task2Ids = relatedResults.map((s) => s.id).toSet();
    final task3Ids = genreResults.map((s) => s.id).toSet();
    final seedArtistKeys = seeds
        .map((s) => primaryArtistKey(s.artist))
        .where((k) => k.isNotEmpty)
        .toSet();

    // Rank personalized candidates: blend related artists + user's taste genres without stripping earned languages.
    final personalizedCandidates = [...relatedResults, ...genreResults];
    final personalizedScored = <Song, double>{};
    for (final song in personalizedCandidates) {
      if (song.isPodcast || !isSingleSong(song)) continue;

      double score = 50.0;
      final songGenre = inferGenre(song);
      final songArtistKey = primaryArtistKey(song.artist);

      if (tasteProfile.genreWeights.containsKey(songGenre)) {
        score += 25.0;
      }

      if (task2Ids.contains(song.id)) {
        // Boost related-artist tracks slightly above same-artist repetitions so variety stays fresh
        final isSeedArtist = songArtistKey.isNotEmpty && seedArtistKeys.contains(songArtistKey);
        score += isSeedArtist ? 15.0 : 28.0;
      }

      if (task3Ids.contains(song.id)) {
        score += 18.0;
      }

      for (final artist in tasteProfile.topArtists) {
        if (song.artist.toLowerCase().contains(artist.toLowerCase())) {
          score += 18.0;
          break;
        }
      }

      if (tasteProfile.listenedSongIds.contains(song.id)) {
        score -= 25.0;
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

    final blendedResult = _blendIntoSlotsWithOrigins(
      trendingPool: trendingPool,
      personalizedPool: personalizedPool,
      task2HistoryIds: task2Ids,
      task3GenreIds: task3Ids,
    );

    final candidateSongs = <Song>[...blendedResult.songs];
    var finalSongs = diversifyAndCapQuickPicks(
      candidateSongs,
      activeSong: activeSong,
      maxPerArtist: 2,
    );

    // Ensure Quick Picks fills at least 4 columns x 4 rows (16 tracks minimum)
    // whenever additional eligible baseline-language tracks are available.
    if (finalSongs.length < 16) {
      final backfillLangs = activeLanguages.take(3).toList();
      final backfillTasks = backfillLangs.map((lang) async {
        final config = getLanguageConfig(lang, allSelectedLanguages: activeLanguages);
        final query = mood != 'All'
            ? '${config.language} $mood songs'
            : (config.language == 'English'
                ? 'top english ${tasteProfile.dominantGenre.toLowerCase()} songs'
                : '${config.language} ${tasteProfile.dominantGenre} hits');
        try {
          final res = await InnerTubeService.search(
            query,
            filter: SearchFilter.songs,
            gl: config.gl,
            hl: config.hl,
          );
          return res.songs
              .where((s) => _isEligibleTrackForConfig(s, config))
              .toList();
        } catch (_) {
          return <Song>[];
        }
      });

      final backfillLists = await Future.wait(backfillTasks);
      final maxBackfill = backfillLists.fold<int>(
        0,
        (max, list) => list.length > max ? list.length : max,
      );
      final combinedWithBackfill = <Song>[...finalSongs];
      for (int i = 0; i < maxBackfill; i++) {
        for (final list in backfillLists) {
          if (i < list.length) {
            combinedWithBackfill.add(list[i]);
          }
        }
      }
      finalSongs = diversifyAndCapQuickPicks(
        combinedWithBackfill,
        activeSong: activeSong,
        maxPerArtist: 2,
      );
    }

    final cleanedSongs = finalSongs.map((s) {
      final cleanedArtist = InnerTubeService.cleanArtistText(s.artist);
      if (cleanedArtist.isEmpty || cleanedArtist == s.artist) {
        return s;
      }
      return s.copyWith(artist: cleanedArtist);
    }).toList();

    final historyDesc = seeds.isNotEmpty
        ? seeds.map((s) => '"${s.title}" (${s.id})').join(', ')
        : 'none';
    LogService.info(
      'getPersonalizedQuickPicks activeLanguages=$activeLanguages mood=$mood seeds=[$historyDesc] Task1=${trendingPool.length} Task2=${relatedResults.length} Task3=${genreResults.length} personalized=${personalizedPool.length} final=${cleanedSongs.length}',
      tag: 'Feed',
    );
    final top6Log = cleanedSongs.take(6).toList().asMap().entries.map((entry) {
      final idx = entry.key;
      final s = entry.value;
      final origin = blendedResult.slotOrigins[s.id] ?? 'backfill';
      return '#$idx "${s.title}" (${s.id}) [$origin]';
    }).join(' | ');
    LogService.info(
      'Final Top 6 Quick Picks ($activeLanguages, mood=$mood): $top6Log',
      tag: 'Feed',
    );

    return cleanedSongs;
  }

  /// Fetches strictly podcast shows and episodes respecting selected languages as baseline.
  static Future<({List<BrowseMediaItem> shows, List<Song> episodes})> getPodcastsFeed({
    List<String>? languages,
    bool forceRefresh = false,
  }) async {
    final activeLanguages = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();
    final effectiveLangs = activeLanguages.isNotEmpty ? activeLanguages : const ['English'];
    final cacheKey = effectiveLangs.join(',');

    if (!forceRefresh) {
      final disk = DatabaseService.getCachedPodcasts(cacheKey);
      final fresh = disk.timestamp != null &&
          DateTime.now().difference(disk.timestamp!) < _browseCacheTtl;
      if (fresh && (disk.shows.isNotEmpty || disk.episodes.isNotEmpty)) {
        return (shows: disk.shows, episodes: disk.episodes);
      }
    }

    final primaryConfig = getLanguageConfig(
      effectiveLangs.first,
      allSelectedLanguages: effectiveLangs,
    );

    bool isEligiblePodcastShow(BrowseMediaItem show, LanguageConfig config) {
      if (show.type != 'podcast' || show.id.isEmpty || show.title.isEmpty) return false;
      if (config.language == 'English') {
        final combined = '${show.title} ${show.subtitle}';
        if (_isExcludedForConfig(combined, config)) return false;
        if (_nonLatinScriptRegex.hasMatch(combined)) return false;
        if (isLikelyForeignLatinTrack(Song(id: show.id, title: show.title, artist: show.subtitle, thumbnailUrl: ''))) {
          return false;
        }
      }
      return true;
    }

    bool isEligiblePodcastEpisode(Song ep, LanguageConfig config) {
      if (!ep.isPodcast || ep.id.isEmpty || ep.title.isEmpty) return false;
      if (config.language == 'English') {
        final combined = '${ep.title} ${ep.artist}';
        if (_isExcludedForConfig(combined, config)) return false;
        if (_nonLatinScriptRegex.hasMatch(combined)) return false;
        if (isLikelyHindiTrack(ep) || isLikelyForeignLatinTrack(ep)) return false;
      }
      return true;
    }

    final browseFuture = primaryConfig.useCountryCharts
        ? InnerTubeService.getPodcastsBrowse(gl: primaryConfig.gl, hl: primaryConfig.hl)
        : Future.value((shows: const <BrowseMediaItem>[], episodes: const <Song>[]));

    final perLangSearchFutures = effectiveLangs.take(3).map((lang) async {
      final config = getLanguageConfig(lang, allSelectedLanguages: effectiveLangs);
      final query = config.language == 'English'
          ? 'popular english podcast'
          : '${config.language} podcast';
      final res = await InnerTubeService.searchPodcasts(
        query,
        gl: config.gl,
        hl: config.hl,
      );
      return (
        config: config,
        shows: res.shows.where((s) => isEligiblePodcastShow(s, config)).toList(),
        episodes: res.episodes.where((e) => isEligiblePodcastEpisode(e, config)).toList(),
      );
    });

    final browseRes = await browseFuture;
    final langSearchRes = await Future.wait(perLangSearchFutures);

    final shows = <BrowseMediaItem>[];
    final seenShows = <String>{};
    final episodes = <Song>[];
    final seenEps = <String>{};

    // Interleave language-targeted shows & episodes first, then browse hub items
    final maxShows = langSearchRes.fold<int>(0, (m, r) => r.shows.length > m ? r.shows.length : m);
    for (int i = 0; i < maxShows; i++) {
      for (final r in langSearchRes) {
        if (i < r.shows.length && seenShows.add(r.shows[i].id)) {
          shows.add(r.shows[i]);
        }
      }
    }
    for (final s in browseRes.shows) {
      if (isEligiblePodcastShow(s, primaryConfig) && seenShows.add(s.id)) {
        shows.add(s);
      }
    }

    final maxEps = langSearchRes.fold<int>(0, (m, r) => r.episodes.length > m ? r.episodes.length : m);
    for (int i = 0; i < maxEps; i++) {
      for (final r in langSearchRes) {
        if (i < r.episodes.length && seenEps.add(r.episodes[i].id)) {
          episodes.add(r.episodes[i]);
        }
      }
    }
    for (final e in browseRes.episodes) {
      if (isEligiblePodcastEpisode(e, primaryConfig) && seenEps.add(e.id)) {
        episodes.add(e);
      }
    }

    if (shows.isNotEmpty || episodes.isNotEmpty) {
      await DatabaseService.saveCachedPodcasts(
        cacheKey,
        shows: shows,
        episodes: episodes,
      );
      return (shows: shows, episodes: episodes);
    }

    final staleDisk = DatabaseService.getCachedPodcasts(cacheKey);
    return (shows: staleDisk.shows, episodes: staleDisk.episodes);
  }

  /// Sequences a balanced autoplay queue from [candidates] seeded by [seedSong],
  /// mixing both related-artist and same-artist tracks while deduplicating against
  /// session history and preventing back-to-back same-artist flooding.
  @visibleForTesting
  static List<Song> buildAutoplayMix({
    required Song seedSong,
    required List<Song> candidates,
    Set<String> excludeIds = const {},
    Set<String> excludeNormalizedKeys = const {},
    int limit = 15,
  }) {
    final seedArtist = primaryArtistKey(seedSong.artist);
    final seedNorm = normalizeTrackKey(seedSong.title);
    final seenIds = <String>{seedSong.id, ...excludeIds};
    final seenSignatures = <String>{
      if (seedNorm.isNotEmpty)
        (seedArtist.isNotEmpty ? '$seedNorm|$seedArtist' : seedNorm),
      ...excludeNormalizedKeys,
    };

    final sameArtistPool = <Song>[];
    final relatedArtistPool = <Song>[];

    for (final s in candidates) {
      if (s.isPodcast != seedSong.isPodcast) continue;
      if (!seedSong.isPodcast && !isSingleSong(s)) continue;
      if (!seenIds.add(s.id)) continue;

      final normTitle = normalizeTrackKey(s.title);
      final artistKey = primaryArtistKey(s.artist);
      if (seedNorm.isNotEmpty && normTitle == seedNorm) continue;

      final sig = artistKey.isNotEmpty ? '$normTitle|$artistKey' : normTitle;
      if (normTitle.isNotEmpty && !seenSignatures.add(sig)) continue;

      final cleanedArtist = InnerTubeService.cleanArtistText(s.artist);
      final cleanSong = (cleanedArtist.isNotEmpty && cleanedArtist != s.artist)
          ? s.copyWith(artist: cleanedArtist)
          : s;

      if (seedArtist.isNotEmpty && artistKey == seedArtist) {
        if (sameArtistPool.length < 4) {
          sameArtistPool.add(cleanSong);
        }
      } else {
        relatedArtistPool.add(cleanSong);
      }
    }

    // Mix related-artist and same-artist tracks while avoiding back-to-back same artist
    final mixed = <Song>[];
    var lastArtist = seedArtist;
    final usedIndicesSame = <int>{};
    final usedIndicesRelated = <int>{};

    Song? pickNextFrom(List<Song> pool, Set<int> used, {required bool avoidLastArtist}) {
      for (int i = 0; i < pool.length; i++) {
        if (used.contains(i)) continue;
        final ak = primaryArtistKey(pool[i].artist);
        if (!avoidLastArtist || ak.isEmpty || ak != lastArtist) {
          used.add(i);
          return pool[i];
        }
      }
      return null;
    }

    // Desired cadence: related -> same -> related -> related -> same ...
    final preferRelatedPattern = [true, false, true, true, false, true, true, false];
    int step = 0;
    while (mixed.length < limit &&
        (usedIndicesRelated.length < relatedArtistPool.length ||
            usedIndicesSame.length < sameArtistPool.length)) {
      final preferRelated = step < preferRelatedPattern.length
          ? preferRelatedPattern[step]
          : (step % 3 != 1);
      step++;

      Song? next;
      if (preferRelated) {
        next = pickNextFrom(relatedArtistPool, usedIndicesRelated, avoidLastArtist: true) ??
            pickNextFrom(sameArtistPool, usedIndicesSame, avoidLastArtist: true) ??
            pickNextFrom(relatedArtistPool, usedIndicesRelated, avoidLastArtist: false) ??
            pickNextFrom(sameArtistPool, usedIndicesSame, avoidLastArtist: false);
      } else {
        next = pickNextFrom(sameArtistPool, usedIndicesSame, avoidLastArtist: true) ??
            pickNextFrom(relatedArtistPool, usedIndicesRelated, avoidLastArtist: true) ??
            pickNextFrom(sameArtistPool, usedIndicesSame, avoidLastArtist: false) ??
            pickNextFrom(relatedArtistPool, usedIndicesRelated, avoidLastArtist: false);
      }

      if (next == null) break;
      mixed.add(next);
      lastArtist = primaryArtistKey(next.artist);
    }

    return mixed;
  }

  /// Fetches smart autoplay recommendations seeded from [seedSong] (matching its vibe/language
  /// without stripping unselected languages the user chose to play).
  static Future<List<Song>> getAutoplayRecommendations(
    Song seedSong, {
    Set<String> excludeIds = const {},
    Set<String> excludeNormalizedKeys = const {},
    int limit = 15,
  }) async {
    if (seedSong.isPodcast) return const [];

    final candidates = <Song>[];
    try {
      final related = await InnerTubeService.getRelatedSongs(seedSong.id);
      candidates.addAll(related);
    } catch (_) {}

    if (candidates.length < 6) {
      try {
        final cleanArtist = InnerTubeService.cleanArtistText(seedSong.artist);
        final genre = inferGenre(seedSong);
        final query = (cleanArtist.isNotEmpty &&
                cleanArtist.toLowerCase() != 'unknown' &&
                cleanArtist.toLowerCase() != 'unknown artist')
            ? '$cleanArtist ${genre != 'Pop' ? genre : ''} songs'.trim()
            : '$genre hits songs';
        final searchRes = await InnerTubeService.search(
          query,
          filter: SearchFilter.songs,
        );
        candidates.addAll(searchRes.songs);
      } catch (_) {}
    }

    return buildAutoplayMix(
      seedSong: seedSong,
      candidates: candidates,
      excludeIds: excludeIds,
      excludeNormalizedKeys: excludeNormalizedKeys,
      limit: limit,
    );
  }
}
