import 'package:flutter/material.dart';

import 'screens/review_history_screen.dart';
import 'screens/review_screen.dart';
import 'services/review_store.dart';
import 'widgets/document_uploader.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reviewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Reviewer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Future<void> _openDocument(
  BuildContext context, {
  required String fileName,
  required String sourcePath,
}) async {
  final store = ReviewStore();
  final versions = await store.listVersions(fileName: fileName, legacySourcePath: sourcePath);
  if (!context.mounted) return;

  if (versions.isNotEmpty) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewHistoryScreen(
          fileName: fileName,
          sourcePath: sourcePath,
          store: store,
        ),
      ),
    );
    return;
  }

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final version = await store.startNewVersion(sourcePath: sourcePath, fileName: fileName);
    if (!context.mounted) return;
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewScreen(
          version: version,
          versionNumber: 1,
          sourcePath: sourcePath,
          store: store,
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Không lưu được bản review: $error')));
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final AiSettingsStore _aiSettingsStore = AiSettingsStore();
  final StructureTemplateStore _templateStore = StructureTemplateStore();

  AiSettings? _aiSettings;
  StructureTemplateLibrary? _templates;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final settings = await _aiSettingsStore.load();
      final templates = await _templateStore.load();
      if (!mounted) return;
      setState(() {
        _aiSettings = settings;
        _templates = templates;
      });
    } catch (_) {
      // No app data directory (e.g. in widget tests); the config card
      // simply stays in its loading state.
    }
  }

  Future<void> _editAiSettings() async {
    if (await showAiSettingsDialog(context) != null) await _loadConfig();
  }

  Future<void> _manageTemplates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const StructureTemplatesScreen()),
    );
    await _loadConfig();
  }

  Future<void> _selectTemplate(String? id) async {
    final library = StructureTemplateLibrary(templates: _templates!.templates, selectedId: id);
    setState(() => _templates = library);
    await _templateStore.save(library);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DocumentUploader(
              onDocumentSelected: (file) {
                final path = file?.path;
                if (file == null || path == null) return;
                _openDocument(context, fileName: file.name, sourcePath: path);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// AI provider and structure template settings shown above the document
/// picker, so they're chosen before a document is opened.
class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.aiSettings,
    required this.templates,
    required this.onEditAiSettings,
    required this.onSelectTemplate,
    required this.onManageTemplates,
  });

  final AiSettings? aiSettings;
  final StructureTemplateLibrary? templates;
  final VoidCallback onEditAiSettings;
  final ValueChanged<String?> onSelectTemplate;
  final VoidCallback onManageTemplates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = aiSettings;
    final library = templates;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Cấu hình AI'),
              subtitle: settings == null
                  ? const Text('Đang tải…')
                  : Text(
                      settings.apiKey.isEmpty
                          ? '${settings.provider.label} · chưa có API key'
                          : '${settings.provider.label} · ${settings.model}',
                      style: settings.apiKey.isEmpty ? TextStyle(color: theme.colorScheme.error) : null,
                    ),
              trailing: OutlinedButton(onPressed: onEditAiSettings, child: const Text('Thay đổi')),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Mẫu cấu trúc tài liệu'),
              subtitle: library == null
                  ? const Text('Đang tải…')
                  : DropdownButton<String?>(
                      isExpanded: true,
                      value: library.selected?.id,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Không dùng mẫu (theo IEEE 830)')),
                        for (final t in library.templates) DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: onSelectTemplate,
                    ),
              trailing: OutlinedButton(onPressed: onManageTemplates, child: const Text('Quản lý mẫu')),
            ),
          ],
        ),
      ),
    );
  }
}
