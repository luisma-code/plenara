import 'package:flutter/material.dart';
import 'package:plenara/config.dart';

import 'app_log.dart';

/// The settings surface (Spec 07 §2.6): view the data folder + diagnostics log path, and set the
/// BYOK Anthropic key in-app (no more hand-editing config.json). The key's VALUE is never shown —
/// only whether one is set. [configPath] is injectable for tests.
class SettingsView extends StatefulWidget {
  final String? configPath;
  const SettingsView({super.key, this.configPath});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _keyCtrl = TextEditingController();
  late PlenaraConfig _cfg = loadConfig(configPath: widget.configPath);

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final key = _keyCtrl.text.trim();
    saveConfig(dataDir: _cfg.dataDir, apiKey: key.isEmpty ? null : key, configPath: widget.configPath);
    _keyCtrl.clear();
    setState(() => _cfg = loadConfig(configPath: widget.configPath));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved — restart Plenara to apply.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: cs.inversePrimary),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Data folder', style: TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(_cfg.dataDir),
          const Divider(height: 32),
          Row(children: [
            const Text('Anthropic API key', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Chip(key: const Key('key-status'), label: Text(_cfg.apiKey != null ? 'set ✓' : 'not set')),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Paste a new key (BYOK)…', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
          const SizedBox(height: 4),
          const Text('Stored locally; only sent to Anthropic when a cloud feature runs. Offline features work without it.',
              style: TextStyle(fontSize: 12)),
          const Divider(height: 32),
          const Text('Diagnostics log', style: TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(AppLog.instance.file.path),
        ],
      ),
    );
  }
}
