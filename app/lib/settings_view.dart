import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';

import 'app_log.dart';

/// The settings surface (Spec 07 §2.6): view the data folder + diagnostics log path, and connect
/// the BYOK Anthropic key in-app. Because Anthropic offers NO third-party OAuth / subscription /
/// programmatic key path (verified 2026), copy-paste is the only compliant mechanism — so this
/// makes it near-foolproof: a deep-link to the Console, a live "Test connection" that names the
/// exact problem (rejected key vs. the #1 gotcha, a valid key with no billing/credits set up), and
/// auto-save on success. The key VALUE is never shown — only whether one is set. [configPath],
/// [openUrl] and [validateKey] are injectable for tests.
class SettingsView extends StatefulWidget {
  final String? configPath;
  final Future<void> Function(String url)? openUrl;
  final Future<CloudResult<String>> Function(String key)? validateKey;
  const SettingsView({super.key, this.configPath, this.openUrl, this.validateKey});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _keysUrl = 'https://console.anthropic.com/settings/keys';
  final _keyCtrl = TextEditingController();
  late PlenaraConfig _cfg = loadConfig(configPath: widget.configPath);
  String? _statusMsg;
  Color? _statusColor;
  bool _testing = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _defaultOpen(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {/* the URL is also shown as copyable text as a fallback */}
  }

  Future<CloudResult<String>> _defaultValidate(String key) => ClaudeClient(apiKeyOverride: key).validateKey();

  void _save() {
    final key = _keyCtrl.text.trim();
    saveConfig(dataDir: _cfg.dataDir, apiKey: key.isEmpty ? null : key, configPath: widget.configPath);
    _keyCtrl.clear();
    setState(() {
      _cfg = loadConfig(configPath: widget.configPath);
      _statusMsg = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved — restart Plenara to apply.')));
    }
  }

  /// Live probe: validate the pasted key, name the exact problem, and save on success.
  Future<void> _test() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() {
        _statusMsg = 'Paste a key first.';
        _statusColor = Colors.orange;
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusMsg = 'Testing your key…';
      _statusColor = null;
    });
    final res = await (widget.validateKey ?? _defaultValidate)(key);
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (res is CloudOk<String>) {
        saveConfig(dataDir: _cfg.dataDir, apiKey: key, configPath: widget.configPath);
        _cfg = loadConfig(configPath: widget.configPath);
        _keyCtrl.clear();
        _statusMsg = "Connected ✓ — your key works and it's saved. Restart Plenara to apply.";
        _statusColor = Colors.green;
      } else if (res is CloudError<String>) {
        _statusMsg = _friendly(res.kind);
        _statusColor = res.kind == CloudErrorKind.insufficientCredits ? Colors.orange : Colors.red;
      }
    });
  }

  String _friendly(CloudErrorKind k) => switch (k) {
        CloudErrorKind.badKey =>
          'That key was rejected. Recopy the whole key (it starts with “sk-ant-”) — it’s shown only once, so create a fresh one if needed.',
        CloudErrorKind.insufficientCredits =>
          'Your key works, but your Anthropic account has no credits yet. In the Console, open Billing → add a payment method (new accounts get free trial credits), then Test again.',
        CloudErrorKind.offline => "Couldn't reach Anthropic — check your internet connection and try again.",
        CloudErrorKind.timeout => "Anthropic didn't respond in time — try again.",
        CloudErrorKind.rateLimited => 'Rate-limited right now — wait a moment and Test again.',
        CloudErrorKind.noKey => 'Paste a key first.',
        _ => 'Unexpected response from Anthropic — try again in a moment.',
      };

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n. ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ]),
      );

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
            const Text('Connect Claude', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 8),
            Chip(key: const Key('key-status'), label: Text(_cfg.apiKey != null ? 'connected ✓' : 'not connected')),
          ]),
          const SizedBox(height: 6),
          const Text('Plenara uses your own Anthropic account, so your notes stay private and you pay Anthropic '
              'directly — typically a few cents a month. It’s a one-time setup:'),
          const SizedBox(height: 10),
          _step('1', 'Open the Anthropic Console (button below) and sign in or sign up.'),
          _step('2', 'Under Billing, add a payment method — new accounts get free trial credits to start.'),
          _step('3', 'Create an API key, then copy it (it’s shown only once).'),
          _step('4', 'Paste it below and press Test connection.'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => (widget.openUrl ?? _defaultOpen)(_keysUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Anthropic Console'),
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(_keysUrl, style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 16),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Paste your key (sk-ant-…)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Test connection'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _save, child: const Text('Save without testing')),
          ]),
          if (_statusMsg != null) ...[
            const SizedBox(height: 10),
            Text(_statusMsg!, style: TextStyle(color: _statusColor, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 8),
          Text('Your key is stored locally and only ever sent to Anthropic when a cloud feature runs. '
              'Everything else works offline without it.', style: TextStyle(fontSize: 12, color: cs.outline)),
          const Divider(height: 32),
          const Text('Diagnostics log', style: TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(AppLog.instance.file.path),
        ],
      ),
    );
  }
}
