import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update.dart';
import '../services/app_update_state_store.dart';
import '../utils/app_theme.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.info,
    required this.stateStore,
  });

  final AppUpdateInfo info;
  final AppUpdateStateStore stateStore;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final content = AlertDialog(
      backgroundColor: AppTheme.panel,
      title: Text(widget.info.isForce ? '必须升级后继续使用' : widget.info.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本 ${widget.info.versionName} · ${_formatSize(widget.info.fileSizeBytes)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            if (widget.info.releaseNotes.isEmpty)
              const Text('这个版本包含稳定性与体验改进。')
            else
              ...widget.info.releaseNotes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(note)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!widget.info.isForce)
          TextButton(
            onPressed: _opening ? null : _dismiss,
            child: const Text('稍后'),
          ),
        FilledButton.icon(
          onPressed: _opening ? null : _openDownload,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_browser_rounded),
          label: const Text('立即升级'),
        ),
      ],
    );

    if (!widget.info.isForce) {
      return content;
    }
    return PopScope(
      canPop: false,
      child: content,
    );
  }

  Future<void> _dismiss() async {
    await widget.stateStore.dismissOptionalUpdate(
      widget.info.versionCode,
      DateTime.now(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openDownload() async {
    final uri = Uri.tryParse(widget.info.downloadUrl);
    if (uri == null) {
      _showError('下载地址不可用');
      return;
    }
    setState(() {
      _opening = true;
    });
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: widget.info.downloadUrl));
        _showError('无法打开浏览器，下载地址已复制');
        return;
      }
      if (mounted && !widget.info.isForce) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: widget.info.downloadUrl));
      _showError('无法打开浏览器，下载地址已复制');
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) {
      return '大小未知';
    }
    final mb = bytes / 1024 / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}
