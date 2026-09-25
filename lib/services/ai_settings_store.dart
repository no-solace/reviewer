import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_settings.dart';

/// Stores [AiSettings] (provider, API keys, models) in the app's data
/// directory. A provider with no saved key falls back to its environment
/// variable (e.g. `ANTHROPIC_API_KEY`).
class AiSettingsStore {
  /// The saved settings, without environment fallbacks applied — for the
  /// settings dialog, so it never writes an env key into the file.
  Future<AiSettings> loadSaved() async {
    final file = await _file();
    if (!await file.exists()) return const AiSettings();

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final legacyKey = json['apiKey'];
    if (legacyKey is String) {
      // Written by the first version, which only supported Claude.
      return AiSettings(apiKeys: {AiProvider.anthropic: legacyKey});
    }
    return AiSettings.fromJson(json);
  }

  /// The settings to run with: saved values, with each missing API key
  /// filled from its provider's environment variable.
  Future<AiSettings> load() async {
    final saved = await loadSaved();
    return saved.copyWith(
      apiKeys: {
        for (final provider in AiProvider.values)
          provider: saved.apiKeyFor(provider).isNotEmpty
              ? saved.apiKeyFor(provider)
              : Platform.environment[provider.envVar]?.trim() ?? '',
      },
    );
  }

  Future<void> save(AiSettings settings) async {
    final file = await _file();
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<File> _file() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return File('${appSupportDir.path}/ai_settings.json');
  }
}
