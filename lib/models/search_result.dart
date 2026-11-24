import 'song.dart';

enum SearchFilter {
  all('All', null),
  songs('Songs', 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D'),
  videos('Videos', 'EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D'),
  albums('Albums', 'EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D'),
  artists('Artists', 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D'),
  playlists('Playlists', 'EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D');

  final String label;
  final String? params;
  const SearchFilter(this.label, [this.params]);
}

class SearchResult {
  final dynamic topResult;
  final List<Song> songs;
  final List<Song> videos;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;

  const SearchResult({
    this.topResult,
    this.songs = const [],
    this.videos = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      topResult == null &&
      songs.isEmpty &&
      videos.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty;
}
