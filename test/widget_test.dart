import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:melody/models/song.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/providers/library_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.init();
  });

  group('Melody Core Logic Tests', () {
    test('Song model serialization and duration format', () {
      const song = Song(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        duration: 213, // 3:33
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );

      expect(song.formattedDuration, '3:33');
      final json = song.toJson();
      final fromJson = Song.fromJson(json);

      expect(fromJson.id, song.id);
      expect(fromJson.title, song.title);
      expect(fromJson.artist, song.artist);
      expect(fromJson.duration, song.duration);
    });

    test('LRC synced lyrics parser', () {
      const sampleLrc = '''
[00:12.34] We're no strangers to love
[00:16.80] You know the rules and so do I
[00:21.05] A full commitment's what I'm thinking of
''';

      final parsed = LyricsData.parseLrc(sampleLrc);
      expect(parsed.length, 3);
      expect(parsed[0].timeMs, 12340);
      expect(parsed[0].text, "We're no strangers to love");
      expect(parsed[1].timeMs, 16800);
      expect(parsed[1].text, 'You know the rules and so do I');
      expect(parsed[2].timeMs, 21050);
    });

    test('DatabaseService and LibraryProvider favorites management', () async {
      const song = Song(
        id: 'test_123',
        title: 'Test Song',
        artist: 'Test Artist',
        thumbnailUrl: '',
      );

      final provider = LibraryProvider();
      expect(provider.isLiked(song.id), isFalse);

      await provider.toggleLike(song);
      expect(provider.isLiked(song.id), isTrue);
      expect(provider.likedSongs.length, 1);

      await provider.toggleLike(song);
      expect(provider.isLiked(song.id), isFalse);
      expect(provider.likedSongs.isEmpty, isTrue);
    });

    test('Custom Playlist creation and song addition', () async {
      final provider = LibraryProvider();
      await provider.createPlaylist('Chill Vibes', description: 'My favorite lo-fi');

      expect(provider.playlists.length, 1);
      final playlist = provider.playlists.first;
      expect(playlist.title, 'Chill Vibes');
      expect(playlist.songs.isEmpty, isTrue);

      const song = Song(
        id: 'lofi_1',
        title: 'Cozy Morning',
        artist: 'Lofi Girl',
        thumbnailUrl: '',
      );

      await provider.addSongToPlaylist(playlist.id, song);
      expect(provider.playlists.first.songs.length, 1);
      expect(provider.playlists.first.songs.first.title, 'Cozy Morning');

      await provider.deletePlaylist(playlist.id);
      expect(provider.playlists.isEmpty, isTrue);
    });
  });
}
