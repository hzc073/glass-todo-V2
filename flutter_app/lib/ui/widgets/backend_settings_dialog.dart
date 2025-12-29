import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

Future<String?> showBackendSettingsDialog(
  BuildContext context, {
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _BackendSettingsDialog(initialValue: initialValue),
  );
}

class _BackendSettingsDialog extends StatefulWidget {
  const _BackendSettingsDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_BackendSettingsDialog> createState() => _BackendSettingsDialogState();
}

class _BackendSettingsDialogState extends State<_BackendSettingsDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const localhostUrl = 'http://localhost:3000';

    return AlertDialog(
      title: const Text('后端地址设置'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: '后端地址',
                hintText:
                    'e.g. http://localhost:3000',
                helperText: '留空将使用默认地址',
                errorText: _errorText,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text(_isAndroid
                        ? '填入 localhost:3000（adb reverse）'
                        : '填入 localhost:3000'),
                    onPressed: () {
                      _controller.text = localhostUrl;
                      setState(() => _errorText = null);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '修改后会影响登录与数据加载。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _handleSave,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _handleSave() {
    final raw = _controller.text.trim();
    if (raw.isNotEmpty) {
      final uri = Uri.tryParse(raw);
      final isHttp = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      final hasHost = uri != null && (uri.host.isNotEmpty || uri.path.isNotEmpty);
      if (!isHttp || !hasHost) {
        setState(() => _errorText =
            '请输入完整地址，例如 http://localhost:3000');
        return;
      }
    }
    Navigator.of(context).pop(raw);
  }
}
