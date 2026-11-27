import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/build_flags.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio_cache_service.dart';
import '../../services/audio_service.dart';
import '../../services/battery_service.dart';
import '../../services/database_service.dart';
import '../../services/innertube_version_manager.dart';
import '../../services/log_service.dart';
import '../../services/stream_resolver_service.dart';
import '../../services/update_service.dart';
import '../components/language_selection_dialog.dart';
import '../components/update_dialog.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late bool _skipSilence;
  late String _quality;
  late bool _autoCheckUpdates;
  late String _updateSource;
  bool _isCheckingUpdate = false;
  String _currentVersion = '1.0.0';
  bool _isBatteryUnrestricted = true;
  bool _backgroundPlayback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _skipSilence = DatabaseService.getSkipSilence();
    _quality = DatabaseService.getAudioQuality();
    _autoCheckUpdates = DatabaseService.getAutoCheckUpdates();
    _updateSource = DatabaseService.getUpdateSource();
    DatabaseService.getBackgroundPlaybackEnabled().then((val) {
      if (mounted) setState(() => _backgroundPlayback = val);
    });
    UpdateService.getCurrentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
    _checkBatteryStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryStatus();
    }
  }

  Future<void> _checkBatteryStatus() async {
    final status = await BatteryService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() => _isBatteryUnrestricted = status);
    }
  }

  Future<void> _checkForUpdatesManually() async {
    setState(() => _isCheckingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to check for updates. Check your internet or update source URL.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (info.hasUpdate) {
      UpdateDialog.show(context, info);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Melody is up to date (v${info.currentVersion})!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static const String _defaultUpdateSource =
      'https://api.github.com/repos/justabean0/melody/releases/latest';

  Color _successColor(ColorScheme colorScheme) {
    return colorScheme.brightness == Brightness.dark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF165B24);
  }

  Color _warningColor(ColorScheme colorScheme) {
    return colorScheme.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFF7A4800);
  }

  void _editUpdateSourceDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _UpdateSourceDialog(
        initialUrl: _updateSource,
        defaultUrl: _defaultUpdateSource,
        onSaved: (newUrl) {
          setState(() => _updateSource = newUrl);
          DatabaseService.setUpdateSource(newUrl);
        },
      ),
    );
  }

  void _showInnerTubeDetailsDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final successColor = _successColor(colorScheme);
    final warningColor = _warningColor(colorScheme);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.tune_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text('InnerTube Engine Health')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YouTube requires client version strings to process playback requests. '
              'When Google deprecates older strings, Melody alerts you and automatically '
              'rotates through safe fallback profiles.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Client Profiles Pool:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            ...InnerTubeVersionManager.allProfiles.map((p) {
              final isDeprecated =
                  InnerTubeVersionManager.isProfileDeprecated(p);
              final isCurrent =
                  InnerTubeVersionManager.currentProfile.key == p.key;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Icon(
                      isDeprecated
                          ? Icons.cancel_outlined
                          : (isCurrent
                              ? Icons.check_circle
                              : Icons.circle_outlined),
                      size: 16,
                      color: isDeprecated
                          ? colorScheme.error
                          : (isCurrent
                              ? successColor
                              : colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p.clientName} v${p.clientVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                          decoration:
                              isDeprecated ? TextDecoration.lineThrough : null,
                          color: isDeprecated
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Text(
                        'ACTIVE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: successColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (InnerTubeVersionManager.isOutdatedWarningActive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Warning: ${InnerTubeVersionManager.outdatedReason ?? 'Outdated string detected'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: warningColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              InnerTubeVersionManager.reset();
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('InnerTube client profiles reset & re-enabled.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Reset Profiles'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _streamingQualitySubtitle(String quality) {
    switch (DatabaseService.normalizeAudioQuality(quality)) {
      case 'Medium':
        return 'Balanced (~128kbps)';
      case 'Low':
        return 'Data saver (~48–64kbps)';
      case 'High':
      default:
        return 'Highest available (Opus / AAC 160kbps+)';
    }
  }

  Future<void> _onQualityChanged(String? val) async {
    if (val == null || val == _quality) return;
    final normalized = DatabaseService.normalizeAudioQuality(val);
    setState(() => _quality = normalized);
    await DatabaseService.setAudioQuality(normalized);
    StreamResolverService.clearCache();
    await AudioCacheService.clearHeadCache();
  }

  Future<void> _onSkipSilenceChanged(bool val) async {
    setState(() => _skipSilence = val);
    await DatabaseService.setSkipSilence(val);
    await MelodyAudioService().setSkipSilence(val);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;
    final successColor = _successColor(colorScheme);
    final warningColor = _warningColor(colorScheme);
    final batteryColor = _isBatteryUnrestricted ? successColor : warningColor;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          children: [
            Text(
              'Settings',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),

            // Card 1: Appearance
            _SettingsSectionCard(
              title: 'Appearance',
              children: [
                _ThemePresetsStrip(themeProvider: themeProvider),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.brightness_auto_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Theme Mode'),
                  subtitle: Text(
                    themeProvider.themeMode == ThemeMode.system
                        ? 'System default'
                        : themeProvider.themeMode == ThemeMode.dark
                            ? 'Dark theme'
                            : 'Light theme',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: _SettingsMenuPill<ThemeMode>(
                    menuKey: const Key('settings_theme_mode_menu'),
                    tooltip: 'Select Theme Mode',
                    value: themeProvider.themeMode,
                    onChanged: themeProvider.setThemeMode,
                    options: const [
                      _SettingsMenuOption(
                        value: ThemeMode.system,
                        label: 'System',
                      ),
                      _SettingsMenuOption(
                        value: ThemeMode.light,
                        label: 'Light',
                      ),
                      _SettingsMenuOption(
                        value: ThemeMode.dark,
                        label: 'Dark',
                      ),
                    ],
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.layers_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Surface Style'),
                  subtitle: Text(
                    themeProvider.surfaceStyle.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: _SettingsMenuPill<ThemeSurfaceStyle>(
                    menuKey: const Key('settings_surface_style_menu'),
                    tooltip: 'Select Surface Style',
                    value: themeProvider.surfaceStyle,
                    onChanged: themeProvider.setSurfaceStyle,
                    options: ThemeSurfaceStyle.values
                        .map(
                          (style) => _SettingsMenuOption(
                            value: style,
                            label: style.label,
                          ),
                        )
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Accent Color',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            ThemeProvider.accentNameFor(
                              themeProvider.accentColor,
                            ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 2,
                        runSpacing: 4,
                        children: ThemeProvider.accentPresets.map((preset) {
                          final isSelected =
                              ThemeProvider.argb32(themeProvider.accentColor) ==
                                  ThemeProvider.argb32(preset.color);
                          final checkColor =
                              ThemeProvider.bestContrastInk(preset.color);
                          return Tooltip(
                            message: preset.name,
                            child: Semantics(
                              label: preset.name,
                              selected: isSelected,
                              button: true,
                              child: InkWell(
                                key: Key('accent_swatch_${preset.name}'),
                                onTap: () =>
                                    themeProvider.setAccentColor(preset.color),
                                customBorder: const CircleBorder(),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      width: 29,
                                      height: 29,
                                      decoration: BoxDecoration(
                                        color: preset.color,
                                        shape: BoxShape.circle,
                                        border: !isSelected
                                            ? Border.all(
                                                color: colorScheme.outlineVariant
                                                    .withValues(alpha: 0.72),
                                                width: 1,
                                              )
                                            : null,
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: colorScheme
                                                      .surfaceContainerLow,
                                                  spreadRadius: 2,
                                                ),
                                                BoxShadow(
                                                  color: colorScheme.onSurface,
                                                  spreadRadius: 4,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: isSelected
                                          ? Icon(
                                              Icons.check_rounded,
                                              color: checkColor,
                                              size: 16,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  key: const Key('settings_adaptive_player_tint_switch'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  secondary: Icon(
                    Icons.palette_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Adaptive Player Tint'),
                  subtitle: Text(
                    'Subtly tint Now Playing surfaces from active album art',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  value: themeProvider.adaptivePlayerTint,
                  onChanged: themeProvider.setAdaptivePlayerTint,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 2: Audio & Playback
            _SettingsSectionCard(
              title: 'Audio & Playback',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.headphones_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Streaming Quality'),
                  subtitle: Text(
                    _streamingQualitySubtitle(_quality),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: _SettingsMenuPill<String>(
                    menuKey: const Key('settings_streaming_quality_menu'),
                    tooltip: 'Select Streaming Quality',
                    value: _quality,
                    onChanged: _onQualityChanged,
                    options: const [
                      _SettingsMenuOption(value: 'High', label: 'High'),
                      _SettingsMenuOption(value: 'Medium', label: 'Medium'),
                      _SettingsMenuOption(value: 'Low', label: 'Low'),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  secondary: Icon(
                    Icons.fast_forward_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Skip Silence'),
                  subtitle: Text(
                    'Automatically skip quiet sections',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  value: _skipSilence,
                  onChanged: _onSkipSilenceChanged,
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  secondary: Icon(
                    Icons.play_circle_outline_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Background Playback'),
                  subtitle: Text(
                    'Keep playback alive after swiping the app from Recents',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  value: _backgroundPlayback,
                  onChanged: (val) async {
                    setState(() => _backgroundPlayback = val);
                    await DatabaseService.setBackgroundPlaybackEnabled(val);
                  },
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  secondary: Icon(
                    _isBatteryUnrestricted
                        ? Icons.battery_charging_full_rounded
                        : Icons.warning_amber_rounded,
                    color: batteryColor,
                  ),
                  title: const Text('Unrestricted Battery'),
                  subtitle: Text(
                    _isBatteryUnrestricted
                        ? 'Unrestricted — background audio will not be killed by OS'
                        : 'Optimized — tap to exempt Melody from battery throttling',
                    style: TextStyle(color: batteryColor),
                  ),
                  value: _isBatteryUnrestricted,
                  onChanged: (val) async {
                    if (val) {
                      await BatteryService.requestIgnoreBatteryOptimizations();
                    } else {
                      await BatteryService.openBatteryOptimizationSettings();
                    }
                    await _checkBatteryStatus();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 3: Content & Recommendations
            _SettingsSectionCard(
              title: 'Content & Recommendations',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.translate_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Music Languages'),
                  subtitle: Text(
                    DatabaseService.getMusicLanguages().join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: () {
                    LanguageSelectionDialog.show(
                      context,
                      isDismissible: true,
                      onSaved: (_) {
                        setState(() {});
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 4: Lyrics & Sync
            _SettingsSectionCard(
              title: 'Lyrics & Sync',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.lyrics_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Lyrics Provider'),
                  subtitle: Text(
                    'LrcLib & Kugou Synced Lyrics',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 5: App Updates
            _SettingsSectionCard(
              title: 'App Updates',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.system_update_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Check for Updates'),
                  subtitle: Text(
                    'Installed version: v$_currentVersion',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: _isCheckingUpdate
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  onTap: _isCheckingUpdate ? null : _checkForUpdatesManually,
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  secondary: Icon(
                    Icons.notifications_active_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Auto-check for updates'),
                  subtitle: Text(
                    'Check for new releases in the background',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  value: _autoCheckUpdates,
                  onChanged: (val) {
                    setState(() => _autoCheckUpdates = val);
                    DatabaseService.setAutoCheckUpdates(val);
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.cloud_sync_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Update Source URL'),
                  subtitle: Text(
                    _updateSource,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: _editUpdateSourceDialog,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 6: InnerTube Engine Health
            _SettingsSectionCard(
              title: 'InnerTube Engine Health',
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.tune_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Client Version String'),
                  subtitle: Text(
                    '${InnerTubeVersionManager.currentProfile.clientName} v${InnerTubeVersionManager.currentProfile.clientVersion}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Builder(
                    builder: (_) {
                      final isOutdated =
                          InnerTubeVersionManager.isOutdatedWarningActive;
                      final badgeColor =
                          isOutdated ? warningColor : successColor;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: badgeColor),
                        ),
                        child: Text(
                          isOutdated ? 'Outdated' : 'Healthy',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: _showInnerTubeDetailsDialog,
                ),
              ],
            ),

            if (kIsDiagnosticsEnabled) ...[
              const SizedBox(height: 14),
              // Card 7: Diagnostics & Debugging
              _SettingsSectionCard(
                title: 'Diagnostics & Debugging',
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: Icon(
                      Icons.bug_report_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Diagnostics & System Logs'),
                    subtitle: Text(
                      'Inspect runtime logs, copy error reports, and monitor streaming',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: ValueListenableBuilder<int>(
                      valueListenable: LogService.logCountNotifier,
                      builder: (context, _, __) {
                        final errCount = LogService.errorCount;
                        if (errCount > 0) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.error.withValues(alpha: 0.45),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '$errCount error${errCount > 1 ? "s" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Card 8: About
            _SettingsSectionCard(
              title: 'About',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 52,
                            height: 52,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.music_note_rounded,
                              color: colorScheme.primary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Melody',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v$_currentVersion • Pure Audio Freedom',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('About Melody'),
                  subtitle: Text(
                    'Material 3 YouTube Music Client',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Melody',
                      applicationVersion: 'v$_currentVersion',
                      applicationIcon: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.music_note, size: 48),
                          ),
                        ),
                      ),
                      children: const [
                        Text(
                          'Melody is a high-performance Material 3 YouTube Music client written in Dart & Flutter.\n'
                          'Features real-time synced lyrics, background streaming, dynamic theming, queue management, and offline favorites.',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final isHighContrast = context.select<ThemeProvider, bool>(
      (t) => t.surfaceStyle == ThemeSurfaceStyle.highContrast,
    );
    final hairlineColor = colorScheme.outlineVariant.withValues(
      alpha: isHighContrast ? 0.72 : (isDark ? 0.25 : 0.45),
    );

    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: colorScheme.primary,
          ),
        ),
      ),
    ];

    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 52,
            endIndent: 16,
            color: hairlineColor,
          ),
        );
      }
      items.add(children[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: isHighContrast
            ? Border.all(color: colorScheme.outlineVariant, width: 1.0)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }
}

class _ThemePresetsStrip extends StatelessWidget {
  final ThemeProvider themeProvider;

  const _ThemePresetsStrip({required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activePreset = themeProvider.activePreset;
    final textScaler = MediaQuery.textScalerOf(context);
    final stripHeight = (68.0 + textScaler.scale(26.0)).clamp(94.0, 132.0);
    final cardWidth = (88.0 + textScaler.scale(24.0)).clamp(110.0, 146.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Theme Presets',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  activePreset?.name ?? 'Custom',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: activePreset != null
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: stripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: ThemeProvider.curatedPresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final preset = ThemeProvider.curatedPresets[index];
                final isSelected = activePreset?.id == preset.id;
                return _ThemePresetCard(
                  preset: preset,
                  width: cardWidth,
                  isSelected: isSelected,
                  onTap: () => themeProvider.applyPreset(preset),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  final ThemePreset preset;
  final double width;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePresetCard({
    required this.preset,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewScheme = ThemeProvider.buildColorScheme(
      seed: preset.accentColor,
      brightness: preset.themeMode == ThemeMode.light
          ? Brightness.light
          : Brightness.dark,
      surfaceStyle: preset.surfaceStyle,
    );

    return Semantics(
      label: '${preset.name} theme preset',
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.36)
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('theme_preset_${preset.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: width,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.65),
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: previewScheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color:
                            previewScheme.outlineVariant.withValues(alpha: 0.7),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 24,
                              height: 8,
                              decoration: BoxDecoration(
                                color: previewScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: previewScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 10,
                                  color: previewScheme.onPrimary,
                                ),
                              )
                            else
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: previewScheme.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        Container(
                          height: 11,
                          decoration: BoxDecoration(
                            color: previewScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 0.58,
                            child: Container(
                              height: 3.5,
                              decoration: BoxDecoration(
                                color: previewScheme.onSurface
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsMenuOption<T> {
  final T value;
  final String label;

  const _SettingsMenuOption({
    required this.value,
    required this.label,
  });
}

class _SettingsMenuPill<T> extends StatelessWidget {
  final Key? menuKey;
  final String tooltip;
  final T value;
  final ValueChanged<T> onChanged;
  final List<_SettingsMenuOption<T>> options;

  const _SettingsMenuPill({
    this.menuKey,
    required this.tooltip,
    required this.value,
    required this.onChanged,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedLabel = options
            .where((o) => o.value == value)
            .map((o) => o.label)
            .firstOrNull ??
        options.first.label;

    return PopupMenuButton<T>(
      key: menuKey,
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onChanged,
      itemBuilder: (_) => options.map((option) {
        final isSelected = option.value == value;
        return PopupMenuItem<T>(
          value: option.value,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: isSelected
                ? BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isSelected)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  )
                else
                  const SizedBox(width: 18),
              ],
            ),
          ),
        );
      }).toList(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
          maxWidth: 180,
        ),
        child: Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateSourceDialog extends StatefulWidget {
  final String initialUrl;
  final String defaultUrl;
  final ValueChanged<String> onSaved;

  const _UpdateSourceDialog({
    required this.initialUrl,
    required this.defaultUrl,
    required this.onSaved,
  });

  @override
  State<_UpdateSourceDialog> createState() => _UpdateSourceDialogState();
}

class _UpdateSourceDialogState extends State<_UpdateSourceDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final newUrl = _controller.text.trim();
    final uri = Uri.tryParse(newUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _errorText = 'Enter a valid http(s) URL');
      return;
    }
    widget.onSaved(newUrl);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Update Source URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter a GitHub Release endpoint or direct manifest URL:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'https://api.github.com/repos/owner/repo/releases/latest',
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _controller.text = widget.defaultUrl;
            _controller.selection =
                TextSelection.collapsed(offset: _controller.text.length);
            if (_errorText != null) setState(() => _errorText = null);
          },
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
