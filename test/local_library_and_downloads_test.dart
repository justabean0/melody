import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/download_service.dart';
import 'package:melody/services/local_audio_service.dart';
import 'package:melody/services/native_extractor_service.dart';
import 'package:melody/services/stream_resolver_service.dart';
import 'package:melody/ui/screens/library_screen.dart';
import 'package:melody/ui/screens/liked_songs_screen.dart';
import 'package:melody/ui/screens/player_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _LibraryPlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isShuffle = false;
  int playSongCalls = 0;
  Song? lastPlayedSong;
  List<Song>? lastContextQueue;
  int? lastStartIndex;
  int toggleShuffleCalls = 0;

  void setShuffleForTesting(bool value) {
    _isShuffle = value;
    notifyListeners();
  }

  void seedCurrent(Song song) {
    _currentSong = song;
    _queue = [song];
    _currentIndex = 0;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Song? get currentSong => _currentSong;
  @override
  List<Song> get queue => List.unmodifiable(_queue);
  @override
  int get currentIndex => _currentIndex;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isLoading => false;
  @override
  Duration get position => const Duration(seconds: 10);
  @override
  Duration get duration => const Duration(seconds: 180);
  @override
  MelodyLoopMode get loopMode => MelodyLoopMode.off;
  @override
  bool get isShuffle => _isShuffle;
  @override
  LyricsData? get lyrics => null;
  @override
  bool get isLoadingLyrics => false;
  @override
  int get activeLyricIndex => -1;

  @override
  Future<void> playSong(
    Song song, {
    List<Song>? contextQueue,
    int? startIndex,
  }) async {
    playSongCalls++;
    lastPlayedSong = song;
    lastContextQueue = contextQueue != null ? List<Song>.from(contextQueue) : null;
    lastStartIndex = startIndex;
    _currentSong = song;
    _queue = contextQueue != null ? List<Song>.from(contextQueue) : [song];
    _currentIndex = startIndex ?? 0;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> togglePlayPause() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> playNext() async {}
  @override
  Future<void> playPrevious() async {}
  @override
  Future<void> seek(Duration position) async {}

  @override
  void toggleShuffle() {
    toggleShuffleCalls++;
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  @override
  void cycleLoopMode() {}
  @override
  void setPlaybackSpeed(double speed) {}
  @override
  void addToQueue(Song song) {}
  @override
  void playNextInQueue(Song song) {}
  @override
  void removeFromQueue(int index) {}
  @override
  void clearQueue() {}
}

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  final List<AudioSource> loadedSources = [];
  Duration currentPosition = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  bool _playing = false;

  void emitPosition(Duration pos) {
    currentPosition = pos;
    _positionController.add(pos);
  }

  void emitState(bool playing, ProcessingState processingState) {
    _playing = playing;
    _processingState = processingState;
    _stateController.add(PlayerState(playing, processingState));
  }

  Future<void> closeStreams() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Duration get position => currentPosition;

  @override
  ProcessingState get processingState => _processingState;

  @override
  bool get playing => _playing;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loadedSources.add(source);
    currentPosition = initialPosition ?? Duration.zero;
    _processingState = ProcessingState.ready;
    _durationController.add(const Duration(seconds: 180));
    emitState(false, ProcessingState.ready);
    return const Duration(seconds: 180);
  }

  @override
  Future<void> play() async {
    emitState(true, ProcessingState.ready);
  }

  @override
  Future<void> pause() async {
    emitState(false, ProcessingState.ready);
  }

  @override
  Future<void> stop() async {
    emitState(false, ProcessingState.idle);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      emitPosition(position);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setSkipSilenceEnabled(bool skipSilenceEnabled) async {}

  @override
  Future<void> dispose() async {
    await closeStreams();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Database? memoryDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    AntiBotService.reset();
    StreamResolverService.clearCache();
    StreamResolverService.clientOverride = null;
    NativeExtractorService.testResolver = null;
    NativeExtractorService.testQualityResolver = null;
    DownloadService().reset();

    SharedPreferences.setMockInitialValues({});
    memoryDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    DatabaseService.setDatabaseForTesting(memoryDb);
    await DatabaseService.init();
  });

  tearDown(() async {
    StreamResolverService.clearCache();
    StreamResolverService.clientOverride = null;
    NativeExtractorService.testResolver = null;
    NativeExtractorService.testQualityResolver = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(LocalAudioService.channelName),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.melody.music/playback'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      null,
    );
    DownloadService().reset();
    DatabaseService.setDatabaseForTesting(null);
    DatabaseService.setPrefsForTesting(null);
    await memoryDb?.close();
    memoryDb = null;
  });

  Widget wrapApp({
    required Widget child,
    required LibraryProvider library,
    required PlaybackProvider playback,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: child,
      ),
    );
  }

  group('Library Overhaul & LikedSongsScreen Tests', () {
    testWidgets(
      'displays Overview | Playlists | Local tabs, replaces Recently Liked with History, navigates to LikedSongsScreen, and plays favorites sequentially',
      (tester) async {
        const fav1 = Song(
          id: 'fav_1',
          title: 'First Liked Song',
          artist: 'Artist One',
          duration: 200,
          thumbnailUrl: '',
        );
        const fav2 = Song(
          id: 'fav_2',
          title: 'Second Liked Song',
          artist: 'Artist Two',
          duration: 185,
          thumbnailUrl: '',
        );
        const histTrack = Song(
          id: 'hist_only',
          title: 'Recently Played Track',
          artist: 'History Artist',
          duration: 210,
          thumbnailUrl: '',
        );

        await DatabaseService.toggleLike(fav1);
        await DatabaseService.toggleLike(fav2);
        await DatabaseService.addToHistory(histTrack);

        final library = LibraryProvider();
        final playback = _LibraryPlaybackProvider()..setShuffleForTesting(true);
        final localAudio = LocalAudioService.forTesting();
        final downloads = DownloadService.forTesting();

        await tester.pumpWidget(
          wrapApp(
            library: library,
            playback: playback,
            child: LibraryScreen(
              localAudioService: localAudio,
              downloadService: downloads,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tab names
        expect(find.text('Overview'), findsOneWidget);
        expect(find.text('Playlists'), findsOneWidget);
        expect(find.text('Local'), findsOneWidget);
        expect(find.text('Favorites'), findsNothing);

        // Overview shows History at bottom instead of Recently Liked
        expect(find.text('History'), findsOneWidget);
        expect(find.text('Recently Played Track'), findsOneWidget);
        expect(find.text('Recently Liked'), findsNothing);

        // Tapping Play button on Liked Songs hero card clears shuffle and plays sequential queue at index 0
        await tester.tap(find.byTooltip('Play Liked Songs'));
        await tester.pump();
        expect(playback.isShuffle, isFalse);
        expect(playback.playSongCalls, 1);
        expect(playback.lastStartIndex, 0);
        // Most recently liked track is at index 0 in LibraryProvider.likedSongs
        expect(playback.lastPlayedSong?.id, 'fav_2');
        expect(
          playback.lastContextQueue?.map((s) => s.id).toList(),
          equals(['fav_2', 'fav_1']),
        );

        // Tapping Liked Songs card body pushes LikedSongsScreen
        await tester.tap(find.byKey(const Key('library_liked_songs_card')));
        await tester.pumpAndSettle();

        expect(find.byType(LikedSongsScreen), findsOneWidget);
        expect(find.text('Liked Songs'), findsOneWidget);
        expect(find.text('2 songs'), findsOneWidget);
        expect(find.text('First Liked Song'), findsOneWidget);
        expect(find.text('Second Liked Song'), findsOneWidget);

        // Play All on LikedSongsScreen starts sequential queue at index 0
        await tester.tap(find.byKey(const Key('liked_songs_play_all_button')));
        await tester.pump();
        expect(playback.playSongCalls, 2);
        expect(playback.lastStartIndex, 0);
        expect(playback.lastPlayedSong?.id, 'fav_2');
        expect(
          playback.lastContextQueue?.map((s) => s.id).toList(),
          equals(['fav_2', 'fav_1']),
        );
      },
    );

    testWidgets(
      'Monthly listening sparkline card updates live when listening stats flush',
      (tester) async {
        final library = LibraryProvider();
        final playback = _LibraryPlaybackProvider();
        final localAudio = LocalAudioService.forTesting();
        final downloads = DownloadService.forTesting();

        await tester.pumpWidget(
          wrapApp(
            library: library,
            playback: playback,
            child: LibraryScreen(
              localAudioService: localAudio,
              downloadService: downloads,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('0m'), findsOneWidget);

        // Simulate listening flush (e.g. pause / track completion / app background)
        await DatabaseService.recordListeningSeconds(180);
        await tester.pumpAndSettle();

        expect(find.textContaining('3m'), findsOneWidget);
        expect(find.textContaining('played this month'), findsOneWidget);
      },
    );
  });

  group('M4A Stream Selection & Persistent MediaStore DownloadService Tests',
      () {
    test(
      'resolveDownloadStream prefers highest-bitrate M4A (audio/mp4) and falls back cleanly when absent',
      () async {
        AntiBotService.reset();

        // Case 1: M4A + WebM present -> prefers highest-bitrate M4A even if WebM is slightly higher or equal
        StreamResolverService.clientOverride = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'itag': 251,
                    'mimeType': 'audio/webm; codecs="opus"',
                    'bitrate': 160000,
                    'url': 'https://cdn.example/opus160.webm',
                  },
                  {
                    'itag': 140,
                    'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                    'bitrate': 128000,
                    'url': 'https://cdn.example/aac128.m4a',
                  },
                  {
                    'itag': 141,
                    'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                    'bitrate': 256000,
                    'url': 'https://cdn.example/aac256.m4a',
                  },
                ],
              },
            }),
            200,
          );
        });

        final m4aPicked = await StreamResolverService.resolveDownloadStream('vid_m4a_01');
        expect(m4aPicked.url, 'https://cdn.example/aac256.m4a');
        expect(m4aPicked.mimeType, 'audio/mp4');
        expect(m4aPicked.extension, 'm4a');

        // Case 2: Only WebM present -> falls back cleanly with matching webm extension & audio/webm MIME
        StreamResolverService.clientOverride = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'itag': 251,
                    'mimeType': 'audio/webm; codecs="opus"',
                    'bitrate': 160000,
                    'url': 'https://cdn.example/only_opus.webm',
                  },
                ],
              },
            }),
            200,
          );
        });

        final webmPicked =
            await StreamResolverService.resolveDownloadStream('vid_webm_01');
        expect(webmPicked.url, 'https://cdn.example/only_opus.webm');
        expect(webmPicked.mimeType, 'audio/webm');
        expect(webmPicked.extension, 'webm');
      },
    );

    test(
      'DownloadService streams to temp file, commits via MediaStore channel, cleans up temp file, and reconciles',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('melody_dl_test_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final methodCalls = <MethodCall>[];
        bool tempExistedDuringCommit = false;
        const fakeBytes = [1, 2, 3, 4, 5, 6, 7, 8];

        const channel = MethodChannel(LocalAudioService.channelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
          if (call.method == 'saveTrackToMediaStore') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final tempFile = File(args['tempFilePath'] as String);
            tempExistedDuringCommit = await tempFile.exists() &&
                (await tempFile.readAsBytes()).length == fakeBytes.length;
            return {
              'contentUri': 'content://media/external/audio/media/901',
              'displayName': 'Tum Hi Ho - Arijit Singh.m4a',
              'relativePath': 'Music/Melody/',
            };
          }
          if (call.method == 'scanLocalAudio') {
            return [
              {
                'id': '901',
                'contentUri': 'content://media/external/audio/media/901',
                'title': 'Tum Hi Ho',
                'artist': 'Arijit Singh',
                'durationMs': 262000,
                'dateAdded': 1700000000,
                'relativePath': 'Music/Melody/',
                'displayName': 'Tum Hi Ho - Arijit Singh.m4a',
                'isMelodyDownload': true,
              }
            ];
          }
          return null;
        });

        final localAudio = LocalAudioService.forTesting(channel: channel);
        final mockHttp = MockClient((request) async {
          return http.Response.bytes(
            fakeBytes,
            200,
            headers: {'content-length': '${fakeBytes.length}'},
          );
        });

        final downloadService = DownloadService.forTesting(
          useDefaultPipeline: true,
          httpClient: mockHttp,
          localAudioService: localAudio,
          tempDirectory: tempDir,
          streamResolver: (_) async => const DownloadStreamSelection(
            url: 'https://cdn.example/track_901.m4a',
            mimeType: 'audio/mp4',
            extension: 'm4a',
            bitrateBps: 128000,
            itag: 140,
          ),
        );

        const song = Song(
          id: 'dl_901',
          title: 'Tum Hi Ho',
          artist: 'Arijit Singh',
          duration: 262,
          thumbnailUrl: '',
        );

        final progressHistory = <double>[];
        downloadService.addListener(() {
          progressHistory.add(downloadService.progressFor(song.id));
        });

        final result = await downloadService.downloadSong(song);
        expect(result.status, DownloadStatus.downloaded);
        expect(result.filePath, 'content://media/external/audio/media/901');
        expect(tempExistedDuringCommit, isTrue);
        expect(progressHistory.last, 1.0);
        // Temporary cache directory must be clean after commit
        expect(tempDir.listSync(), isEmpty);
        expect(
          methodCalls.where((c) => c.method == 'saveTrackToMediaStore').length,
          1,
        );

        // Persistence + Reconcile across fresh instance
        final restored = DownloadService.forTesting(
          useDefaultPipeline: true,
          localAudioService: localAudio,
        );
        restored.restorePersistedDownloads();
        expect(restored.isDownloaded(song.id), isTrue);
        expect(
          restored.localUriFor(song),
          'content://media/external/audio/media/901',
        );
        await restored.reconcileWithMediaStore();
        expect(restored.isDownloaded(song.id), isTrue);

        // Error path removes temp file cleanly
        final failingHttp = MockClient((_) async => http.Response('error', 500));
        final failingService = DownloadService.forTesting(
          useDefaultPipeline: true,
          httpClient: failingHttp,
          localAudioService: localAudio,
          tempDirectory: tempDir,
          streamResolver: (_) async => const DownloadStreamSelection(
            url: 'https://cdn.example/fail.m4a',
            mimeType: 'audio/mp4',
            extension: 'm4a',
          ),
        );
        const failSong = Song(
          id: 'dl_fail',
          title: 'Fail Track',
          artist: 'Nobody',
          thumbnailUrl: '',
        );
        final failed = await failingService.downloadSong(failSong);
        expect(failed.status, DownloadStatus.failed);
        expect(tempDir.listSync(), isEmpty);
      },
    );

    test(
      'DownloadService handles multi-chunk 206 Partial Content streams cleanly',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('melody_dl_206_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final fullPayload = List<int>.generate(600000, (i) => i % 251);
        int rangeRequests = 0;
        int? committedBytes;

        const channel = MethodChannel(LocalAudioService.channelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'saveTrackToMediaStore') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            committedBytes =
                await File(args['tempFilePath'] as String).length();
            return {
              'contentUri': 'content://media/external/audio/media/902',
              'displayName': 'Chunked Song - Artist.m4a',
              'relativePath': 'Music/Melody/',
            };
          }
          return [];
        });

        final localAudio = LocalAudioService.forTesting(channel: channel);
        final mockHttp = MockClient((request) async {
          rangeRequests++;
          final rangeHeader = request.headers['range'] ?? '';
          final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(rangeHeader);
          final start = int.parse(match!.group(1)!);
          final requestedEnd = int.parse(match.group(2)!);
          final end = requestedEnd >= fullPayload.length
              ? fullPayload.length - 1
              : requestedEnd;
          final slice = fullPayload.sublist(start, end + 1);
          return http.Response.bytes(
            slice,
            206,
            headers: {
              'content-range': 'bytes $start-$end/${fullPayload.length}',
              'content-length': '${slice.length}',
            },
          );
        });

        final downloadService = DownloadService.forTesting(
          useDefaultPipeline: true,
          httpClient: mockHttp,
          localAudioService: localAudio,
          tempDirectory: tempDir,
          streamResolver: (_) async => const DownloadStreamSelection(
            url: 'https://cdn.example/chunked_902.m4a',
            mimeType: 'audio/mp4',
            extension: 'm4a',
          ),
        );

        const song = Song(
          id: 'dl_902',
          title: 'Chunked Song',
          artist: 'Artist',
          duration: 180,
          thumbnailUrl: '',
        );

        final res = await downloadService.downloadSong(song);
        expect(res.status, DownloadStatus.downloaded);
        expect(rangeRequests, 2);
        expect(committedBytes, fullPayload.length);
        expect(tempDir.listSync(), isEmpty);
      },
    );
  });

  group('Local Tab UI, Local Audio Bypass & Stats Flush Tests', () {
    testWidgets(
      'Local tab renders permission prompt, permanently denied Open Settings state, requests access, lists downloads/device tracks, filters, and plays sequentially',
      (tester) async {
        bool granted = false;
        bool permanentlyDenied = false;
        int requestCount = 0;
        int openSettingsCount = 0;

        const channel = MethodChannel(LocalAudioService.channelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getAudioPermissionStatus':
              return {
                'granted': granted,
                'permanentlyDenied': permanentlyDenied,
              };
            case 'requestAudioPermission':
              requestCount++;
              granted = true;
              return {'granted': true, 'permanentlyDenied': false};
            case 'openAppSettings':
              openSettingsCount++;
              return true;
            case 'scanLocalAudio':
              if (!granted) return [];
              return [
                {
                  'id': '101',
                  'contentUri': 'content://media/external/audio/media/101',
                  'title': 'Downloaded Anthem',
                  'artist': 'Melody Artist',
                  'durationMs': 180000,
                  'dateAdded': 1700000200,
                  'relativePath': 'Music/Melody/',
                  'displayName': 'Downloaded Anthem - Melody Artist.m4a',
                  'isMelodyDownload': true,
                },
                {
                  'id': '102',
                  'contentUri': 'content://media/external/audio/media/102',
                  'title': 'Voice Memo Jam',
                  'artist': 'Local Recorder',
                  'durationMs': 95000,
                  'dateAdded': 1700000100,
                  'relativePath': 'Recordings/',
                  'displayName': 'Voice Memo Jam.mp3',
                  'isMelodyDownload': false,
                },
              ];
          }
          return null;
        });

        final localAudio = LocalAudioService.forTesting(channel: channel);
        final downloads = DownloadService.forTesting(localAudioService: localAudio);
        final library = LibraryProvider();
        final playback = _LibraryPlaybackProvider();

        await tester.pumpWidget(
          wrapApp(
            library: library,
            playback: playback,
            child: LibraryScreen(
              localAudioService: localAudio,
              downloadService: downloads,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Local'));
        await tester.pumpAndSettle();

        // Initially shows Access Local Music card + Grant Access CTA
        expect(find.text('Access Local Music'), findsOneWidget);
        expect(find.byKey(const Key('local_grant_access_button')), findsOneWidget);

        // When permanently denied, shows Open Settings button instead
        localAudio.setTracksForTesting(
          const [],
          hasPermission: false,
          isPermanentlyDenied: true,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('local_open_settings_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('local_open_settings_button')));
        await tester.pump();
        expect(openSettingsCount, 1);

        // Reset to requestable prompt state and grant permission
        localAudio.setTracksForTesting(
          const [],
          hasPermission: false,
          isPermanentlyDenied: false,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('local_grant_access_button')));
        await tester.pumpAndSettle();

        expect(requestCount, 1);
        expect(find.text('2 tracks on device'), findsOneWidget);
        expect(find.text('All (2)'), findsOneWidget);
        expect(find.text('Downloads (1)'), findsOneWidget);
        expect(find.text('Downloaded Anthem'), findsOneWidget);
        expect(find.text('Voice Memo Jam'), findsOneWidget);

        // Filter to Melody Downloads
        await tester.tap(find.text('Downloads (1)'));
        await tester.pumpAndSettle();
        expect(find.text('1 track on device'), findsOneWidget);
        expect(find.text('Downloaded Anthem'), findsOneWidget);
        expect(find.text('Voice Memo Jam'), findsNothing);

        // Tap track -> plays sequential queue
        await tester.tap(find.text('Downloaded Anthem'));
        await tester.pump();
        expect(playback.playSongCalls, 1);
        expect(
          playback.lastPlayedSong?.localUri,
          'content://media/external/audio/media/101',
        );
        expect(playback.lastStartIndex, 0);
        expect(playback.lastContextQueue?.length, 1);
      },
    );

    test(
      'MelodyAudioService bypasses StreamResolverService for local content:// URIs and flushes listening stats on pause and track completion',
      () async {
        final fakePlayer = _FakeAudioPlayer();
        bool resolverInvoked = false;

        NativeExtractorService.testQualityResolver = (id, quality) async {
          resolverInvoked = true;
          return null;
        };

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.melody.music/playback'),
          (_) async => true,
        );

        final library = LibraryProvider();
        final audioService = MelodyAudioService.forTesting(player: fakePlayer);
        audioService.init();

        const localSong = Song(
          id: 'local_42',
          title: 'Local Track',
          artist: 'Device Artist',
          duration: 180,
          thumbnailUrl: '',
          localUri: 'content://media/external/audio/media/42',
          isLocal: true,
        );

        await audioService.playSong(localSong);

        expect(resolverInvoked, isFalse);
        expect(fakePlayer.loadedSources.length, 1);
        final uriSource = fakePlayer.loadedSources.single as UriAudioSource;
        expect(
          uriSource.uri.toString(),
          'content://media/external/audio/media/42',
        );

        // Simulate active playback ticks (2s + 2s = 4s) followed by pause -> flushes immediately
        fakePlayer.emitPosition(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        fakePlayer.emitPosition(const Duration(seconds: 4));
        await Future<void>.delayed(Duration.zero);
        await audioService.pause();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(DatabaseService.getMonthlyListeningSeconds(), 4);
        expect(library.monthlyListeningSeconds, 4);

        // Resume, advance another 3s, and emit ProcessingState.completed -> flushes immediately
        await audioService.resume();
        fakePlayer.emitPosition(const Duration(seconds: 6));
        await Future<void>.delayed(Duration.zero);
        fakePlayer.currentPosition = const Duration(seconds: 7);
        fakePlayer.emitState(true, ProcessingState.completed);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(DatabaseService.getMonthlyListeningSeconds(), 7);
        expect(library.monthlyListeningSeconds, 7);

        await audioService.stop();
        await fakePlayer.closeStreams();
      },
    );

    testWidgets(
      'PlayerScreen shows Downloaded indicator for local tracks without crashing on missing thumbnailUrl',
      (tester) async {
        const localSong = Song(
          id: 'local_77',
          title: 'Offline Song',
          artist: 'Local Artist',
          duration: 190,
          thumbnailUrl: '',
          localUri: 'content://media/external/audio/media/77',
          isLocal: true,
        );

        final playback = _LibraryPlaybackProvider()..seedCurrent(localSong);
        final library = LibraryProvider();
        final downloadService = DownloadService.forTesting();

        await tester.pumpWidget(
          wrapApp(
            library: library,
            playback: playback,
            child: PlayerScreen(downloadService: downloadService),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byKey(const Key('player_download_button')),
            matching: find.byIcon(Icons.download_done_rounded),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
