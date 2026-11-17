import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    final report = LogService.exportAllLogs();
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Diagnostic logs copied to clipboard! Paste them in the chat.')),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Diagnostic Logs?'),
        content: const Text('This will wipe all currently recorded runtime logs in this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Logs', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy all logs to clipboard',
            onPressed: _copyToClipboard,
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
                      color: Colors.redAccent,
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
                      color: Colors.amber,
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

              // System info banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Auto-records network, audio proxy, seeking, and playback state.',
                          style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
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
                            Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matching log entries found.'
                                  : 'No logs recorded yet.',
                              style: const TextStyle(color: Colors.grey),
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
                          return _buildLogTile(item);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Copy Diagnostics & Logs to Clipboard'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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

  Widget _buildLogTile(LogEntry item) {
    final color = switch (item.level) {
      LogLevel.error => Colors.redAccent,
      LogLevel.warning => Colors.amber,
      LogLevel.info => Colors.blueAccent,
      LogLevel.debug => Colors.purpleAccent,
    };

    final icon = switch (item.level) {
      LogLevel.error => Icons.error_rounded,
      LogLevel.warning => Icons.warning_rounded,
      LogLevel.info => Icons.info_rounded,
      LogLevel.debug => Icons.bug_report_rounded,
    };

    return InkWell(
      onTap: () {
        // Show full entry details dialog on tap
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '[${item.tag}] ${item.formattedTime}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                    const SnackBar(content: Text('Log entry copied to clipboard.')),
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
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (item.error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Error: ${item.error}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.redAccent),
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
