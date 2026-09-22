import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A widget that lets the user pick a single document (PDF or Word file)
/// from local storage and reports the selection back to its parent.
class DocumentUploader extends StatefulWidget {
  const DocumentUploader({super.key, this.onDocumentSelected});

  /// Called whenever the user picks a new file, or clears the current one
  /// (with `null`).
  final ValueChanged<PlatformFile?>? onDocumentSelected;

  @override
  State<DocumentUploader> createState() => _DocumentUploaderState();
}

class _DocumentUploaderState extends State<DocumentUploader> {
  static const _allowedExtensions = ['pdf', 'doc', 'docx'];

  PlatformFile? _selectedFile;
  int? _selectedFileSize;
  String? _errorMessage;
  bool _isPicking = false;

  Future<void> _pickDocument() async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
      );

      if (file == null) {
        return;
      }

      final size = file.lengthSync() ?? await file.length();
      setState(() {
        _selectedFile = file;
        _selectedFileSize = size;
      });
      widget.onDocumentSelected?.call(file);
    } catch (e) {
      setState(() => _errorMessage = 'Could not open the file picker: $e');
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _selectedFileSize = null;
      _errorMessage = null;
    });
    widget.onDocumentSelected?.call(null);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForExtension(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _isPicking ? null : _pickDocument,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline,
                style: BorderStyle.solid,
                width: 1.5,
              ),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Column(
              children: [
                if (_isPicking)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(),
                  )
                else
                  Icon(
                    _selectedFile == null
                        ? Icons.upload_file
                        : _iconForExtension(_selectedFile!.extension),
                    size: 40,
                    color: colorScheme.primary,
                  ),
                const SizedBox(height: 12),
                Text(
                  _selectedFile?.name ?? 'Choose a document to upload',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_selectedFile != null && _selectedFileSize != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(_selectedFileSize!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (_selectedFile == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'PDF, DOC or DOCX',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(color: colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _isPicking ? null : _pickDocument,
              icon: const Icon(Icons.folder_open),
              label: Text(_selectedFile == null ? 'Browse' : 'Choose another'),
            ),
            if (_selectedFile != null) ...[
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                label: const Text('Clear'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
