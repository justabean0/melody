import 'song.dart';

class AlbumBrowseResult {
  final String browseId;
  final String? playlistId;
  final String title;
  final String artist;
  final String? artistId;
  final int? year;
  final String thumbnailUrl;
  final String? description;
  final List<Song> songs;
  final List<Album> otherVersions;

  const AlbumBrowseResult({
    required this.browseId,
    this.playlistId,
    required this.title,
    required this.artist,
    this.artistId,
    this.year,
    required this.thumbnailUrl,
    this.description,
    this.songs = const [],
    this.otherVersions = const [],
  });

  String get id => browseId;
  String get thumbnail => thumbnailUrl;

  Album toAlbum() => Album(
        id: browseId,
        playlistId: playlistId,
        title: title,
        artist: artist,
        artistId: artistId,
        year: year,
        thumbnailUrl: thumbnailUrl,
        songCount: songs.length,
        songs: songs,
      );

  Map<String, dynamic> toJson() => {
        'browseId': browseId,
        'playlistId': playlistId,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'year': year,
        'thumbnailUrl': thumbnailUrl,
        'description': description,
        'songs': songs.map((s) => s.toJson()).toList(),
        'otherVersions': otherVersions.map((a) => a.toJson()).toList(),
      };

  factory AlbumBrowseResult.fromJson(Map<String, dynamic> json) =>
      AlbumBrowseResult(
        browseId: json['browseId'] as String? ?? json['id'] as String? ?? '',
        playlistId: json['playlistId'] as String?,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? 'Unknown Artist',
        artistId: json['artistId'] as String?,
        year: json['year'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String? ??
            json['thumbnail'] as String? ??
            '',
        description: json['description'] as String?,
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        otherVersions: (json['otherVersions'] as List<dynamic>?)
                ?.map((a) => Album.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class PlaylistBrowseResult {
  final String browseId;
  final String? playlistId;
  final String title;
  final String? author;
  final String? authorId;
  final String thumbnailUrl;
  final String? description;
  final int songCount;
  final List<Song> songs;

  const PlaylistBrowseResult({
    required this.browseId,
    this.playlistId,
    required this.title,
    this.author,
    this.authorId,
    required this.thumbnailUrl,
    this.description,
    this.songCount = 0,
    this.songs = const [],
  });

  String get id => browseId;
  String get thumbnail => thumbnailUrl;

  Playlist toPlaylist() => Playlist(
        id: browseId,
        playlistId: playlistId,
        title: title,
        author: author,
        description: description,
        thumbnailUrl: thumbnailUrl,
        songCount: songs.isNotEmpty ? songs.length : songCount,
        songs: songs,
      );

  Map<String, dynamic> toJson() => {
        'browseId': browseId,
        'playlistId': playlistId,
        'title': title,
        'author': author,
        'authorId': authorId,
        'thumbnailUrl': thumbnailUrl,
        'description': description,
        'songCount': songCount,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory PlaylistBrowseResult.fromJson(Map<String, dynamic> json) =>
      PlaylistBrowseResult(
        browseId: json['browseId'] as String? ?? json['id'] as String? ?? '',
        playlistId: json['playlistId'] as String?,
        title: json['title'] as String? ?? '',
        author: json['author'] as String?,
        authorId: json['authorId'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String? ??
            json['thumbnail'] as String? ??
            '',
        description: json['description'] as String?,
        songCount: json['songCount'] as int? ?? 0,
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class ArtistBrowseResult {
  final String browseId;
  final String name;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final String? description;
  final String? subscribers;
  final String? monthlyListeners;
  final List<Song> topSongs;
  final List<Album> albums;
  final List<Album> singles;

  const ArtistBrowseResult({
    required this.browseId,
    required this.name,
    this.thumbnailUrl,
    this.bannerUrl,
    this.description,
    this.subscribers,
    this.monthlyListeners,
    this.topSongs = const [],
    this.albums = const [],
    this.singles = const [],
  });

  String get id => browseId;
  String get thumbnail => thumbnailUrl ?? '';
  String? get subscriberCountText => subscribers;

  Artist toArtist() => Artist(
        id: browseId,
        name: name,
        thumbnailUrl: thumbnailUrl,
        subscribers: subscribers,
      );

  Map<String, dynamic> toJson() => {
        'browseId': browseId,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        'bannerUrl': bannerUrl,
        'description': description,
        'subscribers': subscribers,
        'monthlyListeners': monthlyListeners,
        'topSongs': topSongs.map((s) => s.toJson()).toList(),
        'albums': albums.map((a) => a.toJson()).toList(),
        'singles': singles.map((s) => s.toJson()).toList(),
      };

  factory ArtistBrowseResult.fromJson(Map<String, dynamic> json) =>
      ArtistBrowseResult(
        browseId: json['browseId'] as String? ?? json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ??
            json['thumbnail'] as String?,
        bannerUrl: json['bannerUrl'] as String?,
        description: json['description'] as String?,
        subscribers: json['subscribers'] as String?,
        monthlyListeners: json['monthlyListeners'] as String?,
        topSongs: (json['topSongs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        albums: (json['albums'] as List<dynamic>?)
                ?.map((a) => Album.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        singles: (json['singles'] as List<dynamic>?)
                ?.map((s) => Album.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class MoodGenreItem {
  final String title;
  final String browseId;
  final String? params;
  final int? stripeColor;

  const MoodGenreItem({
    required this.title,
    required this.browseId,
    this.params,
    this.stripeColor,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'browseId': browseId,
        'params': params,
        'stripeColor': stripeColor,
      };

  factory MoodGenreItem.fromJson(Map<String, dynamic> json) => MoodGenreItem(
        title: json['title'] as String? ?? '',
        browseId: json['browseId'] as String? ?? '',
        params: json['params'] as String?,
        stripeColor: json['stripeColor'] as int?,
      );
}

class ChartsResult {
  final String countryCode;
  final List<Song> topSongs;
  final List<Song> trendingVideos;
  final List<Playlist> playlists;
  final List<Album> albums;

  const ChartsResult({
    required this.countryCode,
    this.topSongs = const [],
    this.trendingVideos = const [],
    this.playlists = const [],
    this.albums = const [],
  });

  List<Playlist> get chartPlaylists => playlists;
  List<Album> get chartAlbums => albums;

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'topSongs': topSongs.map((s) => s.toJson()).toList(),
        'trendingVideos': trendingVideos.map((s) => s.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'albums': albums.map((a) => a.toJson()).toList(),
      };

  factory ChartsResult.fromJson(Map<String, dynamic> json) => ChartsResult(
        countryCode: json['countryCode'] as String? ?? 'IN',
        topSongs: (json['topSongs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        trendingVideos: (json['trendingVideos'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        playlists: (json['playlists'] as List<dynamic>?)
                ?.map((p) => Playlist.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        albums: (json['albums'] as List<dynamic>?)
                ?.map((a) => Album.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class ExploreResult {
  final List<Album> newReleaseAlbums;
  final List<Song> trendingVideos;
  final List<MoodGenreItem> moodAndGenres;

  const ExploreResult({
    this.newReleaseAlbums = const [],
    this.trendingVideos = const [],
    this.moodAndGenres = const [],
  });

  List<Album> get newReleases => newReleaseAlbums;
  List<Song> get newClips => trendingVideos;
  List<MoodGenreItem> get moodCategories => moodAndGenres;

  Map<String, dynamic> toJson() => {
        'newReleaseAlbums': newReleaseAlbums.map((a) => a.toJson()).toList(),
        'trendingVideos': trendingVideos.map((s) => s.toJson()).toList(),
        'moodAndGenres': moodAndGenres.map((m) => m.toJson()).toList(),
      };

  factory ExploreResult.fromJson(Map<String, dynamic> json) => ExploreResult(
        newReleaseAlbums: (json['newReleaseAlbums'] as List<dynamic>?)
                ?.map((a) => Album.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        trendingVideos: (json['trendingVideos'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        moodAndGenres: (json['moodAndGenres'] as List<dynamic>?)
                ?.map((m) => MoodGenreItem.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class MoodGenreBrowseResult {
  final String title;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Album> albums;

  const MoodGenreBrowseResult({
    required this.title,
    this.songs = const [],
    this.playlists = const [],
    this.albums = const [],
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'songs': songs.map((s) => s.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'albums': albums.map((a) => a.toJson()).toList(),
      };

  factory MoodGenreBrowseResult.fromJson(Map<String, dynamic> json) =>
      MoodGenreBrowseResult(
        title: json['title'] as String? ?? '',
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        playlists: (json['playlists'] as List<dynamic>?)
                ?.map((p) => Playlist.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        albums: (json['albums'] as List<dynamic>?)
                ?.map((a) => Album.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class BrowseMediaItem {
  final String id;
  final String title;
  final String subtitle;
  final String thumbnailUrl;
  final String? browseId;
  final String? params;
  final String type; // 'playlist', 'album', 'genre'

  const BrowseMediaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    this.browseId,
    this.params,
    this.type = 'playlist',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'thumbnailUrl': thumbnailUrl,
        'browseId': browseId,
        'params': params,
        'type': type,
      };

  factory BrowseMediaItem.fromJson(Map<String, dynamic> json) => BrowseMediaItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        browseId: json['browseId'] as String?,
        params: json['params'] as String?,
        type: json['type'] as String? ?? 'playlist',
      );
}

