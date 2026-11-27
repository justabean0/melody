import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/build_flags.dart';
import '../../services/log_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  LogLevel? _selectedFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isUploading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _successColor(ColorScheme colorScheme) {
    return colorScheme.brightness == Brightness.dark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF1B6E2D);
  }

  Color _warningColor(ColorScheme colorScheme) {
    return colorScheme.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFF8A5300);
  }

  void _copyToClipboard() {
    final report = LogService.exportAllLogs();
    Clipboard.setData(ClipboardData(text: report));
    final colorScheme = Theme.of(context).colorScheme;
    final successBg = _successColor(colorScheme);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Diagnostic logs copied to clipboard!')),
          ],
        ),
        backgroundColor: successBg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _shareLogFile() async {
    final success = await LogService.shareLogFile();
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open share sheet. Please try Copy or Upload.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveToDownloads() async {
    final path = await LogService.saveLogToDownloads();
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_done_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Saved log file to $path')),
            ],
          ),
          backgroundColor: _successColor(colorScheme),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save to Downloads.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _uploadAndShowLink() async {
    setState(() => _isUploading = true);
    final url = await LogService.uploadLogToCloud();
    if (!mounted) return;
    setState(() => _isUploading = false);
    final colorScheme = Theme.of(context).colorScheme;

    if (url != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: _successColor(colorScheme)),
              const SizedBox(width: 8),
              const Text('Log Uploaded'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your crash log was securely uploaded. You can download the file from this link on your PC or share it:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  url,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Link'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Download URL copied to clipboard!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload log to cloud. Check internet or use Share File.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmClear() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Diagnostic Logs?'),
        content: const Text('This will wipe all currently recorded runtime logs in this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () {
              setState(() {
                LogService.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsDiagnosticsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnostics')),
        body: const Center(
          child: Text('Diagnostics are disabled in standard release builds.'),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Logs', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Send / Share Log File',
            onPressed: _shareLogFile,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Save to Downloads',
            onPressed: _saveToDownloads,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear logs',
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: LogService.logCountNotifier,
        builder: (context, _, __) {
          final allLogs = LogService.logs.reversed.toList();
          final filteredLogs = allLogs.where((entry) {
            if (_selectedFilter != null && entry.level != _selectedFilter) {
              return false;
            }
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              return entry.message.toLowerCase().contains(q) ||
                  entry.tag.toLowerCase().contains(q) ||
                  (entry.error?.toLowerCase().contains(q) ?? false);
            }
            return true;
          }).toList();

          final totalCount = allLogs.length;
          final errorCount = LogService.errorCount;
          final warnCount = LogService.warningCount;

          return Column(
            children: [
              // Summary cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    _buildMetricCard(
                      label: 'Total Logs',
                      count: totalCount.toString(),
                      icon: Icons.list_alt_rounded,
                      color: colorScheme.primary,
                      onTap: () => setState(() => _selectedFilter = null),
                      isSelected: _selectedFilter == null,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricCard(
                      label: 'Errors',
                      count: errorCount.toString(),
                      icon: Icons.error_outline_rounded,
                      color: colorScheme.error,
                      onTap: () => setState(() {
                        _selectedFilter =
                            _selectedFilter == LogLevel.error ? null : LogLevel.error;
                      }),
                      isSelected: _selectedFilter == LogLevel.error,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricCard(
                      label: 'Warnings',
                      count: warnCount.toString(),
                      icon: Icons.warning_amber_rounded,
                      color: _warningColor(colorScheme),
                      onTap: () => setState(() {
                        _selectedFilter =
                            _selectedFilter == LogLevel.warning ? null : LogLevel.warning;
                      }),
                      isSelected: _selectedFilter == LogLevel.warning,
                    ),
                  ],
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Filter logs by keyword...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear filter',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),

              // Info banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can send or upload the log file below to download it on your PC.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 12),

              // Log Entries List
              Expanded(
                child: filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 48,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matching log entries found.'
                                  : 'No logs recorded yet.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        itemCount: filteredLogs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredLogs[index];
                          return _buildLogTile(item, theme, colorScheme);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Send / Share Log File Button
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _shareLogFile,
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Send / Share File'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Upload to Cloud & Get Download Link
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isUploading ? null : _uploadAndShowLink,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(_isUploading ? 'Uploading...' : 'Get Download Link'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Secondary row: Copy to Clipboard & Save to Downloads
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy to Clipboard', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveToDownloads,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Save to Downloads', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildMetricCard({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(40) : color.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : color.withAlpha(50),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color.withAlpha(220)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogTile(
    LogEntry item,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final color = switch (item.level) {
      LogLevel.error => colorScheme.error,
      LogLevel.warning => _warningColor(colorScheme),
      LogLevel.info => colorScheme.primary,
      LogLevel.debug => colorScheme.tertiary,
    };

    final icon = switch (item.level) {
      LogLevel.error => Icons.error_rounded,
      LogLevel.warning => Icons.warning_rounded,
      LogLevel.info => Icons.info_rounded,
      LogLevel.debug => Icons.bug_report_rounded,
    };

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '[${item.tag}] ${item.formattedTime}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SelectableText(
                'Time: ${item.timestamp.toIso8601String()}\n'
                'Level: ${item.level.name.toUpperCase()}\n'
                'Tag: ${item.tag}\n\n'
                'Message:\n${item.message}\n'
                '${item.error != null ? "\nError: ${item.error}\n" : ""}'
                '${item.stackTrace != null ? "\nStackTrace:\n${item.stackTrace}\n" : ""}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.toString()));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Log entry copied to clipboard.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Copy Entry'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.tag,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.formattedTime,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                  if (item.error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Error: ${item.error}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
