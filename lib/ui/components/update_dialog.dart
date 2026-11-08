import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// Displays the update dialog modally
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  File? _downloadedApk;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      final apkFile = await UpdateService.downloadApk(
        widget.updateInfo.downloadUrl,
        onProgress: (received, total, percent) {
          if (mounted) {
            setState(() {
              _receivedBytes = received;
              _totalBytes = total;
              _progress = percent;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _downloadedApk = apkFile;
      });

      // Automatically launch native package installer
      await UpdateService.installApk(apkFile.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = widget.updateInfo;

    return PopScope(
      canPop: !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Available',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'v${info.currentVersion} ➔ v${info.latestVersion}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isDownloading && _downloadedApk == null) ...[
                if (info.apkSize != null && info.apkSize! > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(Icons.download_outlined, size: 16, color: colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(
                          'Size: ${_formatBytes(info.apkSize!)}',
                          style: TextStyle(fontSize: 12, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                const Text(
                  "What's New:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(128),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        info.changelog.trim().isNotEmpty
                            ? info.changelog.trim()
                            : '• Bug fixes and performance improvements.',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                ),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 8,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloading update...',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                    Text(
                      '${(_progress * 100).toInt()}% (${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
              if (_downloadedApk != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Download complete! Ready to install.',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_isDownloading && _downloadedApk == null) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: _startDownloadAndInstall,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Update Now'),
            ),
          ],
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: Text(
                'Please wait...',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ),
          if (_downloadedApk != null) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => UpdateService.installApk(_downloadedApk!.path),
              icon: const Icon(Icons.install_mobile_rounded, size: 18),
              label: const Text('Install Now'),
            ),
          ],
        ],
      ),
    );
  }
}
