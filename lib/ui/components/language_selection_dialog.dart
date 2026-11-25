import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/innertube_service.dart';
import '../../services/recommendation_service.dart';

class MusicLanguage {
  final String name;
  final String nativeName;
  final String subtitle;

  const MusicLanguage({
    required this.name,
    required this.nativeName,
    required this.subtitle,
  });
}

class LanguageSelectionDialog extends StatefulWidget {
  final bool isDismissible;
  final ValueChanged<List<String>>? onSaved;

  const LanguageSelectionDialog({
    super.key,
    this.isDismissible = true,
    this.onSaved,
  });

  /// Displays the language selection dialog modally
  static Future<void> show(
    BuildContext context, {
    bool isDismissible = true,
    ValueChanged<List<String>>? onSaved,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: isDismissible,
      builder: (ctx) => PopScope(
        canPop: isDismissible,
        child: LanguageSelectionDialog(
          isDismissible: isDismissible,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  State<LanguageSelectionDialog> createState() => _LanguageSelectionDialogState();
}

class _LanguageSelectionDialogState extends State<LanguageSelectionDialog> {
  static const List<MusicLanguage> allLanguages = [
    MusicLanguage(
      name: 'Hindi',
      nativeName: 'हिंदी',
      subtitle: 'Bollywood, Indie & Pop',
    ),
    MusicLanguage(
      name: 'English',
      nativeName: 'English',
      subtitle: 'Global Hits, Pop & Hip-Hop',
    ),
    MusicLanguage(
      name: 'Punjabi',
      nativeName: 'ਪੰਜਾਬੀ',
      subtitle: 'Punjabi Pop, Hip-Hop & Folk',
    ),
    MusicLanguage(
      name: 'Spanish',
      nativeName: 'Español',
      subtitle: 'Reggaeton, Latin Pop & Bachata',
    ),
    MusicLanguage(
      name: 'Korean',
      nativeName: '한국어',
      subtitle: 'K-Pop, K-Drama OST & R&B',
    ),
    MusicLanguage(
      name: 'Bengali',
      nativeName: 'বাংলা',
      subtitle: 'Tollywood, Rabindra Sangeet & Folk',
    ),
    MusicLanguage(
      name: 'Tamil',
      nativeName: 'தமிழ்',
      subtitle: 'Kollywood & Carnatic Beats',
    ),
    MusicLanguage(
      name: 'Telugu',
      nativeName: 'తెలుగు',
      subtitle: 'Tollywood Blockbusters & Melodies',
    ),
    MusicLanguage(
      name: 'Malayalam',
      nativeName: 'മലയാളം',
      subtitle: 'Mollywood Indie & Melodies',
    ),
    MusicLanguage(
      name: 'Kannada',
      nativeName: 'ಕನ್ನಡ',
      subtitle: 'Sandalwood Hits & Pop',
    ),
    MusicLanguage(
      name: 'Bhojpuri',
      nativeName: 'भोजपुरी',
      subtitle: 'Bhojpuri Hits & Desi Folk',
    ),
    MusicLanguage(
      name: 'Marathi',
      nativeName: 'मराठी',
      subtitle: 'Marathi Pop & Folk Hits',
    ),
    MusicLanguage(
      name: 'Japanese',
      nativeName: '日本語',
      subtitle: 'J-Pop, Anime OST & City Pop',
    ),
    MusicLanguage(
      name: 'French',
      nativeName: 'Français',
      subtitle: 'French Pop, Chanson & Rap',
    ),
    MusicLanguage(
      name: 'Arabic',
      nativeName: 'العربية',
      subtitle: 'Arabic Pop, Tarab & Khaleeji',
    ),
    MusicLanguage(
      name: 'Urdu',
      nativeName: 'اردو',
      subtitle: 'Ghazals, Sufi & Coke Studio',
    ),
  ];

  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final initial = DatabaseService.getMusicLanguages();
    _selected = Set<String>.from(initial.isNotEmpty ? initial : ['English']);
  }

  void _toggleLanguage(String name) {
    setState(() {
      if (_selected.contains(name)) {
        if (_selected.length > 1) {
          _selected.remove(name);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select at least 1 language.'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        _selected.add(name);
      }
    });
  }

  Future<void> _saveAndApply() async {
    final list = _selected.toList();
    await DatabaseService.setMusicLanguages(list);
    await DatabaseService.markLanguageOnboardingCompleted();
    InnerTubeService.clearQuickPicksCache();
    RecommendationService.clearCache();
    widget.onSaved?.call(list);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filtered = allLanguages.where((lang) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return lang.name.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q) ||
          lang.subtitle.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: theme.dialogBackgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.translate_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isDismissible
                              ? 'Music Languages'
                              : 'Welcome to Melody',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose your preferred languages for personalized Quick Picks and Trending music.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color?.withAlpha(190),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isDismissible)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Search Bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search language...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withAlpha(100),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),

              const SizedBox(height: 12),

              // Scrollable Grid of Languages (Plain Text Only, No Emojis)
              Flexible(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            'No languages found for "$_searchQuery"',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.disabledColor,
                            ),
                          ),
                        ),
                      )
                    : GridView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) {
                          final lang = filtered[index];
                          final isSelected = _selected.contains(lang.name);

                          return InkWell(
                            onTap: () => _toggleLanguage(lang.name),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primaryContainer.withAlpha(180)
                                    : colorScheme.surfaceContainerHighest.withAlpha(65),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.outline.withAlpha(50),
                                  width: isSelected ? 1.8 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                lang.name,
                                                style: theme.textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (lang.nativeName != lang.name) ...[
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  '(${lang.nativeName})',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isSelected
                                                        ? colorScheme.primary
                                                        : colorScheme.onSurfaceVariant.withAlpha(200),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          lang.subtitle,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontSize: 9.5,
                                            color: theme.textTheme.bodySmall?.color?.withAlpha(170),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected ? colorScheme.primary : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outline.withAlpha(120),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 14),

              // Bottom Info & Confirm Button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected.length} language${_selected.length == 1 ? '' : 's'} selected',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _selected.isNotEmpty ? _saveAndApply : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(widget.isDismissible ? 'Save' : 'Continue to Music'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
