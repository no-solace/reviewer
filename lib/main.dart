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
