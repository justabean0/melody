import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../services/database_service.dart';
import '../services/innertube_service.dart';
import '../services/log_service.dart';

class SearchProvider extends ChangeNotifier {
  int _searchRequestToken = 0;
  int get searchRequestToken => _searchRequestToken;

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
    _searchRequestToken++;
    notifyListeners();
  }

  void onQueryChanged(String text) async {
    _query = text;
    final token = ++_searchRequestToken;
    if (text.trim().isEmpty) {
      _suggestions = [];
      _hasSearched = false;
      notifyListeners();
      return;
    }

    final list = await InnerTubeService.getSearchSuggestions(text);
    if (token != _searchRequestToken) return;
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
    final token = ++_searchRequestToken;

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
    if (token != _searchRequestToken) return;
    notifyListeners();

    try {
      final res = await InnerTubeService.search(clean, filter: _filter);
      if (token != _searchRequestToken) return;
      _results = res;
    } catch (_) {
      if (token != _searchRequestToken) return;
      _results = const SearchResult();
    } finally {
      if (token == _searchRequestToken) {
        _isLoading = false;
        notifyListeners();
      }
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

  void clearSearch() {
    clear();
  }

  void clear() {
    _searchRequestToken++;
    _query = '';
    _suggestions = [];
    _results = const SearchResult();
    _hasSearched = false;
    _isLoading = false;
    notifyListeners();
  }

  @visibleForTesting
  void setResultsForTesting(SearchResult results) {
    _results = results;
    _hasSearched = true;
    _isLoading = false;
    notifyListeners();
  }
}
