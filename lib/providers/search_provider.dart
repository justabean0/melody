import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../services/innertube_service.dart';

class SearchProvider extends ChangeNotifier {
  String _query = '';
  String get query => _query;

  SearchFilter _filter = SearchFilter.all;
  SearchFilter get filter => _filter;

  List<String> _suggestions = [];
  List<String> get suggestions => _suggestions;

  SearchResult _results = const SearchResult();
  SearchResult get results => _results;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasSearched = false;
  bool get hasSearched => _hasSearched;

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
      _suggestions = list;
      notifyListeners();
    }
  }

  Future<void> performSearch(String query) async {
    if (query.trim().isEmpty) return;
    _query = query;
    _isLoading = true;
    _hasSearched = true;
    _suggestions = [];
    notifyListeners();

    try {
      _results = await InnerTubeService.search(query, filter: _filter);
    } catch (_) {
      _results = const SearchResult();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
