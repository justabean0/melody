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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectionHint;

  @override
  void initState() {
    super.initState();
    final initial = DatabaseService.getMusicLanguages();
    _selected = Set<String>.from(initial.isNotEmpty ? initial : ['English']);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleLanguage(String name) {
    setState(() {
      if (_selected.contains(name)) {
        if (_selected.length > 1) {
          _selected.remove(name);
          _selectionHint = null;
        } else {
          _selectionHint = 'Keep at least 1 language selected.';
        }
      } else {
        _selected.add(name);
        _selectionHint = null;
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
      backgroundColor: colorScheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scrollable header, search, and language grid so large font scales
              // and compact viewports never overflow vertically.
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScaler = MediaQuery.textScalerOf(context);
                    final textScale = textScaler.scale(1.0);
                    final crossAxisCount =
                        (constraints.maxWidth < 310 || textScale >= 1.55)
                            ? 1
                            : 2;
                    final tileHeight =
                        (44.0 + textScaler.scale(28.0)).clamp(68.0, 140.0);

                    return CustomScrollView(
                      shrinkWrap: true,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
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
                                    child: Text(
                                      widget.isDismissible
                                          ? 'Music Languages'
                                          : 'Welcome to Melody',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  if (widget.isDismissible)
                                    IconButton(
                                      tooltip: 'Close',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose your preferred languages for personalized Quick Picks and Trending music.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search language...',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Clear language search',
                                          constraints: const BoxConstraints(
                                            minWidth: 48,
                                            minHeight: 48,
                                          ),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                        if (filtered.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'No languages found for "$_searchQuery"',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisExtent: tileHeight,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildLanguageTile(
                                theme,
                                colorScheme,
                                filtered[index],
                              ),
                              childCount: filtered.length,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              if (_selectionHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selectionHint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Bottom Info & Confirm Button
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    '${_selected.length} language${_selected.length == 1 ? '' : 's'} selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _selected.isNotEmpty ? _saveAndApply : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(
                      widget.isDismissible ? 'Save' : 'Continue to Music',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
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

  Widget _buildLanguageTile(
    ThemeData theme,
    ColorScheme colorScheme,
    MusicLanguage lang,
  ) {
    final isSelected = _selected.contains(lang.name);
    return InkWell(
      onTap: () => _toggleLanguage(lang.name),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.72)
              : colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
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
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lang.nativeName != lang.name) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '(${lang.nativeName})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11.5,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
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
                      fontSize: 11,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.85)
                          : colorScheme.onSurfaceVariant,
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
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color:
                      isSelected ? colorScheme.primary : colorScheme.outline,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: colorScheme.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
