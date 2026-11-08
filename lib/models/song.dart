class Song {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final int duration; // in seconds
  final String thumbnailUrl;
  final bool isVideo;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.duration = 0,
    required this.thumbnailUrl,
    this.isVideo = false,
  });

  String get formattedDuration {
    if (duration <= 0) return '0:00';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'album': album,
      'albumId': albumId,
      'duration': duration,
      'thumbnailUrl': thumbnailUrl,
      'isVideo': isVideo,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? 'Unknown Artist',
      artistId: json['artistId'] as String?,
      album: json['album'] as String?,
      albumId: json['albumId'] as String?,
      duration: json['duration'] as int? ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      isVideo: json['isVideo'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Artist {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? subscribers;

  const Artist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        'subscribers': subscribers,
      };

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
        id: json['id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        subscribers: json['subscribers'] as String?,
      );
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final int? year;
  final String thumbnailUrl;
  final int songCount;
  final List<Song> songs;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.year,
    required this.thumbnailUrl,
    this.songCount = 0,
    this.songs = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'year': year,
        'thumbnailUrl': thumbnailUrl,
        'songCount': songCount,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String? ?? 'Unknown Artist',
        artistId: json['artistId'] as String?,
        year: json['year'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        songCount: json['songCount'] as int? ?? 0,
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class Playlist {
  final String id;
  final String title;
  final String? author;
  final String? description;
  final String thumbnailUrl;
  final int songCount;
  final List<Song> songs;

  const Playlist({
    required this.id,
    required this.title,
    this.author,
    this.description,
    required this.thumbnailUrl,
    this.songCount = 0,
    this.songs = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
        'songCount': songCount,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String?,
        description: json['description'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        songCount: json['songCount'] as int? ?? 0,
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
