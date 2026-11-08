import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/database_service.dart';
import '../../services/update_service.dart';
import '../components/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _normalize;
  late bool _skipSilence;
  late String _quality;
  late bool _autoCheckUpdates;
  late String _updateSource;
  bool _isCheckingUpdate = false;
  String _currentVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _normalize = DatabaseService.getNormalizeVolume();
    _skipSilence = DatabaseService.getSkipSilence();
    _quality = DatabaseService.getAudioQuality();
    _autoCheckUpdates = DatabaseService.getAutoCheckUpdates();
    _updateSource = DatabaseService.getUpdateSource();
    UpdateService.getCurrentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
  }

  Future<void> _checkForUpdatesManually() async {
    setState(() => _isCheckingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to check for updates. Check your internet or update source URL.'),
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

  void _editUpdateSourceDialog() {
    final controller = TextEditingController(text: _updateSource);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://api.github.com/repos/owner/repo/releases/latest',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                setState(() => _updateSource = newUrl);
                DatabaseService.setUpdateSource(newUrl);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Section 1: Appearance & Material 3
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Appearance',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_medium),
            title: const Text('Theme Mode'),
            subtitle: Text(
              themeProvider.themeMode == ThemeMode.system
                  ? 'System default'
                  : themeProvider.themeMode == ThemeMode.dark
                      ? 'Dark theme'
                      : 'Light theme',
            ),
            trailing: DropdownButton<ThemeMode>(
              value: themeProvider.themeMode,
              underline: const SizedBox.shrink(),
              onChanged: (mode) {
                if (mode != null) themeProvider.setThemeMode(mode);
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Pure Black (AMOLED)'),
            subtitle: const Text('Pitch black background in dark mode'),
            value: themeProvider.pureBlack,
            onChanged: (val) => themeProvider.setPureBlack(val),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Accent Color', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: ThemeProvider.availableAccents.map((color) {
                    final isSelected = themeProvider.accentColor == color;
                    return GestureDetector(
                      onTap: () => themeProvider.setAccentColor(color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const Divider(),

          // Section 2: Audio & Playback
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Audio & Playback',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('Streaming Quality'),
            subtitle: Text('Highest available (Opus / AAC 160kbps+)'),
            trailing: DropdownButton<String>(
              value: _quality,
              underline: const SizedBox.shrink(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _quality = val);
                  DatabaseService.setAudioQuality(val);
                }
              },
              items: const [
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Audio Normalization'),
            subtitle: const Text('Balances volume levels across tracks'),
            value: _normalize,
            onChanged: (val) {
              setState(() => _normalize = val);
              DatabaseService.setNormalizeVolume(val);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fast_forward_outlined),
            title: const Text('Skip Silence'),
            subtitle: const Text('Automatically skip quiet sections'),
            value: _skipSilence,
            onChanged: (val) {
              setState(() => _skipSilence = val);
              DatabaseService.setSkipSilence(val);
            },
          ),

          const Divider(),

          // Section 3: Lyrics & Extensions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Lyrics & Sync',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.lyrics_outlined),
            title: Text('Lyrics Provider'),
            subtitle: Text('LrcLib & Kugou Synced Lyrics'),
          ),

          const Divider(),

          // Section 4: App Updates
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'App Updates',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('Check for Updates'),
            subtitle: Text('Installed version: v$_currentVersion'),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isCheckingUpdate ? null : _checkForUpdatesManually,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Auto-check for updates'),
            subtitle: const Text('Check for new releases in the background'),
            value: _autoCheckUpdates,
            onChanged: (val) {
              setState(() => _autoCheckUpdates = val);
              DatabaseService.setAutoCheckUpdates(val);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Update Source URL'),
            subtitle: Text(
              _updateSource,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.edit_outlined, size: 20),
            onTap: _editUpdateSourceDialog,
          ),

          const Divider(),

          // Section 5: About Melody
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'About',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Melody Flutter'),
            subtitle: const Text('Version 1.0.0 • Material 3 YouTube Music Client'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Melody',
                applicationVersion: '1.0.0',
                applicationIcon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white, size: 28),
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
    );
  }
}
