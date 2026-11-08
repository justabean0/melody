# Melody (Flutter & Dart)

A modern, high-performance **Material 3 YouTube Music client** built in **Dart & Flutter**, recreated and analyzed with reverse-engineering workflows.

---

## 🌟 Key Features

### 🎧 Playback & Streaming
- **Ad-Free Music Streaming**: Seamless audio playback from YouTube Music with multiplatform support (Windows, Android, iOS, macOS, Web, Linux).
- **High-Fidelity Audio**: Native MP4/AAC & Opus audio stream resolution.
- **Queue & Auto-Mix**: Dynamic queue management with automatic related track generation.
- **Controls**: Shuffle, Repeat modes (Off, All, One), Playback speed (0.75x to 2.0x), and Seek slider.
- **Continuous Playback**: Native background audio playback and track continuity.

### 📝 Synchronized Lyrics
- **Real-Time Synced Lyrics**: Powered by **LrcLib** synchronized lyrics engine.
- **Auto-Scrolling**: Lyrics smoothly scroll and highlight in sync with audio position.
- **Interactive Seeking**: Tap any lyric line to jump directly to that timestamp.
- **Plain Lyrics Fallback**: Clean readable formatting when timestamps are unavailable.

### 🎨 Material 3 & Dynamic Theming
- **Material You Design**: Follows Google Material 3 guidelines.
- **Dynamic Theming**: Choose from signature Melody Crimson Red, Amber, Emerald, Indigo, Pink, and more.
- **Pure Black (AMOLED)**: True black background for OLED screens and battery saving.
- **Adaptive Layout**: Floating Mini Player bar and expandable full-screen Player with gesture controls.

### 🔍 YouTube Music InnerTube Integration
- **Quick Picks**: Personalized home recommendations and trending charts.
- **Search**: Real-time search suggestions with multi-category filtering (Songs, Videos, Albums, Artists, Playlists).
- **Moods & Genres**: Instant filtering for Chill, Workout, Focus, Party, Romance, and Sleep.

### 📚 Local Library & Offline
- **Favorites / Liked Songs**: Save tracks with instant one-tap like toggles.
- **Custom Playlists**: Create, edit, rename, and manage your own playlists.
- **Playback History**: Keep track of recently played songs with clear history option.
- **Offline Persistence**: Fast local storage via SharedPreferences.

---

## 🏗️ Architecture

```
lib/
├── models/
│   ├── song.dart              # Song, Artist, Album, Playlist data entities
│   ├── lyrics.dart            # Synced LyricLine parser & LyricsData
│   └── search_result.dart     # Search filters and categorized results
├── services/
│   ├── innertube_service.dart # YouTube Music InnerTube API & stream resolver
│   ├── audio_service.dart     # MelodyAudioService multiplatform audio player
│   ├── lyrics_service.dart    # LrcLib real-time lyrics API client
│   └── database_service.dart  # Local storage for favorites, playlists, settings
├── providers/
│   ├── playback_provider.dart # Audio state, queue, synced lyrics sync
│   ├── library_provider.dart  # Liked songs, custom playlists, history
│   ├── theme_provider.dart    # Dynamic Material 3 theming & AMOLED black
│   └── search_provider.dart   # Suggestions, query state, filters
├── ui/
│   ├── components/
│   │   ├── mini_player.dart   # Floating bottom mini player bar
│   │   ├── song_tile.dart     # Song list item with menu
│   │   ├── album_card.dart    # Horizontal scroll media card
│   │   └── lyrics_view.dart   # Auto-scrolling synced lyrics
│   └── screens/
│       ├── home_screen.dart   # Melody Quick Picks, Moods, Trending
│       ├── search_screen.dart # Search bar, suggestions, results
│       ├── library_screen.dart# Favorites, Playlists, History tabs
│       ├── settings_screen.dart# Audio, theme, and app preferences
│       └── player_screen.dart # Full-screen player with lyrics & queue tabs
└── main.dart                  # MultiProvider setup & root NavigationBar
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.27+)
- Dart SDK (3.6+)

### Run the App
```bash
flutter pub get
flutter run
```

### Run Tests
```bash
flutter test
flutter analyze
```
