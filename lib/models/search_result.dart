import 'song.dart';

enum SearchFilter {
  all('All'),
  songs('Songs'),
  videos('Videos'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists');

  final String label;
  const SearchFilter(this.label);
}

class SearchResult {
  final List<Song> songs;
  final List<Song> videos;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;

  const SearchResult({
    this.songs = const [],
    this.videos = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      songs.isEmpty &&
      videos.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty;
}
