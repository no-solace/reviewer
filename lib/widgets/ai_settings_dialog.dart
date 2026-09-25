import 'package:flutter/material.dart';

import '../models/ai_settings.dart';
import '../services/ai_settings_store.dart';

/// Opens the AI settings dialog; saves and returns the new settings, or
/// null if the lecturer cancelled.
Future<AiSettings?> showAiSettingsDialog(BuildContext context) async {
  final store = AiSettingsStore();
  final current = await store.loadSaved();
  if (!context.mounted) return null;

  final updated = await showDialog<AiSettings>(
    context: context,
    builder: (context) => _AiSettingsDialog(initial: current),
  );
  if (updated != null) await store.save(updated);
  return updated;
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.initial});

  final AiSettings initial;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  late AiProvider _provider = widget.initial.provider;

  // One controller per provider so switching providers keeps what was typed.
  late final Map<AiProvider, TextEditingController> _keyControllers = {
    for (final p in AiProvider.values) p: TextEditingController(text: widget.initial.apiKeyFor(p)),
  };
  late final Map<AiProvider, TextEditingController> _modelControllers = {
    for (final p in AiProvider.values) p: TextEditingController(text: widget.initial.models[p] ?? ''),
  };
  bool _obscureKey = true;

  @override
  void dispose() {
    for (final c in [..._keyControllers.values, ..._modelControllers.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      AiSettings(
        provider: _provider,
        apiKeys: {for (final e in _keyControllers.entries) e.key: e.value.text.trim()},
        models: {for (final e in _modelControllers.entries) e.key: e.value.text.trim()},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Cấu hình AI'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nhà cung cấp', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<AiProvider>(
              segments: [
                for (final p in AiProvider.values) ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_provider},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _provider = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              key: ValueKey('key-${_provider.name}'),
              controller: _keyControllers[_provider],
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: _provider.keyHint,
                helperText: 'Tạo key tại ${_provider.keyUrl}. '
                    'Để trống sẽ dùng biến môi trường ${_provider.envVar} nếu có.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: ValueKey('model-${_provider.name}'),
              controller: _modelControllers[_provider],
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: _provider.defaultModel,
                helperText: 'Để trống để dùng mặc định: ${_provider.defaultModel}. '
                    'Nên chọn model đọc được PDF và hình ảnh.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Key được lưu trên máy này, trong thư mục dữ liệu của ứng dụng. '
              'Tài liệu sinh viên sẽ được gửi tới nhà cung cấp đã chọn khi chạy kiểm tra.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
