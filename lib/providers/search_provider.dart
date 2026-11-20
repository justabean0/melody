import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../services/database_service.dart';
import '../services/innertube_service.dart';
import '../services/log_service.dart';
import '../services/stream_resolver_service.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  String get query => _query;

  SearchFilter _filter = SearchFilter.all;
  SearchFilter get filter => _filter;

  List<String> _suggestions = [];
  List<String> get suggestions => _suggestions;

  List<String> _history = [];
  List<String> get history => _history;

  SearchResult _results = const SearchResult();
  SearchResult get results => _results;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasSearched = false;
  bool get hasSearched => _hasSearched;

  SearchProvider() {
    _loadHistory();
  }

  void _loadHistory() {
    _history = DatabaseService.getSearchHistory();
  }

  List<String> getMatchingHistory([String? filterQuery]) {
    final q = (filterQuery ?? _query).trim().toLowerCase();
    if (q.isEmpty) return _history;
    return _history.where((item) => item.toLowerCase().contains(q)).toList();
  }

  void setFilter(SearchFilter f) {
    _filter = f;
    notifyListeners();
  }

  void onQueryChanged(String text) async {
    _query = text;
    if (text.trim().isEmpty) {
      _suggestions = [];
      _hasSearched = false;
      notifyListeners();
      return;
    }

    final list = await InnerTubeService.getSearchSuggestions(text);
    if (_query == text) {
      // Exclude items that are already in matching search history to prevent duplicates
      final historyMatches = getMatchingHistory(text).map((h) => h.toLowerCase()).toSet();
      _suggestions = list.where((s) => !historyMatches.contains(s.toLowerCase())).toList();
      notifyListeners();
    }
  }

  Future<void> performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    _query = clean;
    _isLoading = true;
    _hasSearched = true;
    _suggestions = [];

    LogService.recordBreadcrumb(
      'Search performed: "$clean" (${_filter.name})',
      category: 'search',
    );

    // Save to persistent search history immediately
    await DatabaseService.addSearchHistory(clean);
    _history = DatabaseService.getSearchHistory();
    notifyListeners();

    try {
      _results = await InnerTubeService.search(clean, filter: _filter);

      // Speculative Stream Pre-warming:
      // Instantly pre-resolve and pre-cache the 5s audio head for the top 3 results in background
      if (_results.songs.isNotEmpty) {
        final toPreWarm = _results.songs.take(3).toList();
        debugPrint('⚡ [Search Pre-Warming]: Speculatively pre-resolving top ${toPreWarm.length} results for "$clean"...');
        for (final song in toPreWarm) {
          StreamResolverService.preWarm(song.id, songTitle: song.title, artist: song.artist);
        }
      }
    } catch (_) {
      _results = const SearchResult();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeFromHistory(String item) async {
    await DatabaseService.removeSearchHistory(item);
    _history = DatabaseService.getSearchHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await DatabaseService.clearSearchHistory();
    _history = [];
    notifyListeners();
  }

  void clear() {
    _query = '';
    _suggestions = [];
    _results = const SearchResult();
    _hasSearched = false;
    _isLoading = false;
    notifyListeners();
  }
}
