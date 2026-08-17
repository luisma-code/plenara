import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/generative.dart';
import 'package:plenara/turnlog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_log.dart';
import 'credential_store.dart';
import 'data_location.dart';
import 'presence_shell.dart';
import 'voice_setup.dart';

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
  final DiagnosticPolicy? diagnosticPolicy;
  final ValueChanged<bool>? onStillPresenceChanged;
  final Future<String?> Function()? chooseDataFolder;
  const SettingsView({
    super.key,
    this.configPath,
    this.openUrl,
    this.validateKey,
    this.diagnosticPolicy,
    this.onStillPresenceChanged,
    this.chooseDataFolder,
  });
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _keysUrl = 'https://console.anthropic.com/settings/keys';
  final _keyCtrl = TextEditingController();
  late PlenaraConfig _cfg = loadAppConfig(configPath: widget.configPath);
  String? _statusMsg;
  Color? _statusColor;
  bool _testing = false;
  DiagnosticPolicy get _diagnostics =>
      widget.diagnosticPolicy ?? activeDiagnosticPolicy;

  static const _cloudNames = <String, String>{
    'gift_ideas': 'Gift ideas',
    'reconnect': 'Reconnect coaching',
    'briefing': 'Briefing',
    'weekly_review': 'Weekly reflection',
    'pattern_insight': 'Pattern insight',
    'draft_message': 'Message draft',
  };

  Widget _cloudContentSection(ColorScheme cs) => ExpansionTile(
    key: const Key('cloud-content-declarations'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    title: const Text('What each cloud feature sends'),
    subtitle: const Text(
      'Only the record classes listed here, for the feature you ask for.',
    ),
    children: [
      for (final entry in generativeDataClasses.entries)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(_cloudNames[entry.key] ?? entry.key),
          subtitle: Text(
            (entry.value.toList()..sort()).join(', '),
            style: TextStyle(color: cs.outline),
          ),
        ),
      const ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('Journal'),
        subtitle: Text(
          'Never included by these features. A future journal-based feature must ask separately each session.',
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _defaultOpen(String url) async {
    // url_launcher hands the URL to the OS on every platform — critically including iOS, where the
    // old Process.run('open'/'xdg-open') path is forbidden in the sandbox (it silently no-op'd, so
    // the button "did nothing"). externalApplication forces the system browser, not an in-app view.
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* the URL is also shown as copyable text as a fallback */
    }
  }

  Future<CloudResult<String>> _defaultValidate(String key) =>
      ClaudeClient(apiKeyOverride: key).validateKey();

  /// Persist a key + refresh state. Clears the field only if it still holds the SAME key we saved
  /// (so a key typed while a test was in flight isn't wiped — Fable review).
  Future<void> _persist(String key) async {
    await saveAppCredential(key, configPath: widget.configPath);
    _cfg = loadAppConfig(configPath: widget.configPath);
    if (_keyCtrl.text.trim() == key) _keyCtrl.clear();
  }

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      // Don't claim "Saved" while silently changing nothing — empty means "use Disconnect".
      setState(() {
        _statusMsg =
            'Paste a key first — or use Disconnect to remove your key.';
        _statusColor = Colors.orange;
      });
      return;
    }
    try {
      await _persist(key);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMsg =
            'Secure storage could not verify the save. The existing key was not removed; try again.';
        _statusColor = Colors.red;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _statusMsg = 'Saved — restart Plenara to apply.';
      _statusColor = null;
    });
  }

  /// Toggle the per-build paid confirm. Default OFF: asking every time was friction on a request
  /// the user had already made, and it made the app feel like it was haggling.
  void _setConfirmSpend(bool value) {
    saveConfig(
      dataDir: _cfg.dataDir,
      confirmCloudSpend: value,
      configPath: widget.configPath,
    );
    setState(() {
      _cfg = loadAppConfig(configPath: widget.configPath);
      _statusMsg = value
          ? "I'll ask before each paid build — restart Plenara to apply."
          : "I'll just build what you ask for — restart Plenara to apply.";
      _statusColor = null;
    });
  }

  /// Toggle free (offline-only) mode. Persisted now; applied on next launch (like the key),
  /// since the Session is built once at startup.
  void _setFreeTier(bool value) {
    saveConfig(
      dataDir: _cfg.dataDir,
      freeTier: value,
      configPath: widget.configPath,
    );
    setState(() {
      _cfg = loadAppConfig(configPath: widget.configPath);
      _statusMsg = value
          ? 'Free mode on — restart Plenara to run fully offline.'
          : 'Paid mode on — restart Plenara to re-enable cloud features.';
      _statusColor = null;
    });
  }

  void _setStillPresence(bool value) {
    saveConfig(stillPresence: value, configPath: widget.configPath);
    setState(() {
      _cfg = loadAppConfig(configPath: widget.configPath);
      _statusMsg = value
          ? 'Still presence on — Plena will hold expressive static forms.'
          : 'Ambient presence motion restored.';
      _statusColor = null;
    });
    widget.onStillPresenceChanged?.call(value);
  }

  /// Explicitly remove the key ('' clears; null would leave it untouched).
  Future<void> _disconnect() async {
    await saveAppCredential('', configPath: widget.configPath);
    if (!mounted) return;
    setState(() {
      _cfg = loadAppConfig(configPath: widget.configPath);
      _keyCtrl.clear();
      _statusMsg = 'Disconnected. Offline features still work.';
      _statusColor = null;
    });
  }

  Future<void> _chooseDataFolder() async {
    String? selected;
    try {
      selected =
          await (widget.chooseDataFolder ??
              const DataFolderAccess().chooseSelection)();
      if (selected == null || selected.trim().isEmpty || !mounted) return;
      setState(() {
        _statusMsg = 'Moving your Plenara data…';
        _statusColor = null;
      });
      final result = await switchDataFolder(
        currentDataDir: _cfg.dataDir,
        selectedPath: selected,
        configPath: widget.configPath,
      );
      if (!mounted) return;
      setState(() {
        _cfg = loadAppConfig(configPath: widget.configPath);
        _statusMsg = result.copiedExistingData
            ? 'Data copied safely. Restart Plenara to use this folder.'
            : result.adoptedExistingData
            ? 'Existing Plenara folder selected. Restart to open it.'
            : 'Folder selected. Restart Plenara to apply.';
        _statusColor = Colors.green;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMsg = 'Could not use that folder: $error';
        _statusColor = Colors.red;
      });
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
    if (res is CloudOk<String> ||
        res is CloudError<String> &&
            res.kind == CloudErrorKind.insufficientCredits) {
      try {
        await _persist(key);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _statusMsg =
              'The key worked, but secure storage could not verify the save. Nothing was removed; try again.';
          _statusColor = Colors.red;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (res is CloudOk<String>) {
        _statusMsg =
            "Connected ✓ — your key works and it's saved. Restart Plenara to apply.";
        _statusColor = Colors.green;
      } else if (res is CloudError<String>) {
        // A no-credits key AUTHENTICATED — it's valid, so save it (billing is the only gap). The
        // key is shown only once; discarding it would force the user to mint a new one after they
        // add billing (Fable review).
        _statusMsg = _friendly(res.kind);
        _statusColor = res.kind == CloudErrorKind.insufficientCredits
            ? Colors.orange
            : Colors.red;
      }
    });
  }

  String _friendly(CloudErrorKind k) => switch (k) {
    CloudErrorKind.badKey =>
      'That key was rejected. Recopy the whole key (it starts with “sk-ant-”) — it’s shown only once, so create a fresh one if needed.',
    CloudErrorKind.insufficientCredits =>
      'Saved your key — it works. But your Anthropic account has no credits yet: in the Console, open Billing → add a payment method (new accounts get free trial credits), then you’re all set.',
    CloudErrorKind.offline =>
      "Couldn't reach Anthropic — check your internet connection and try again.",
    CloudErrorKind.timeout => "Anthropic didn't respond in time — try again.",
    CloudErrorKind.rateLimited =>
      'Rate-limited right now — wait a moment and Test again.',
    CloudErrorKind.noKey => 'Paste a key first.',
    _ => 'Unexpected response from Anthropic — try again in a moment.',
  };

  /// Load the device-local turnlog (one JSON object per line); empty on any error.
  List<Map<String, dynamic>> _loadTurns() {
    try {
      final f = File('${defaultDeviceDir()}/turnlog.jsonl');
      if (!f.existsSync()) return const [];
      return f
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            try {
              return jsonDecode(l) as Map<String, dynamic>;
            } catch (_) {
              return <String, dynamic>{};
            }
          })
          .where((m) => m.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Widget _usageSection(ColorScheme cs) {
    final turns = _loadTurns();
    Widget row(String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(a, style: const TextStyle(fontSize: 13)),
          Text(
            b,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    final admission = CloudAdmissionController(
      path: widget.configPath == null
          ? '${defaultDeviceDir()}/cloud-usage.json'
          : '${File(widget.configPath!).parent.path}/cloud-usage.json',
    ).snapshot();
    if (turns.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            'Cloud admission today',
            '${admission.dailyUsed} / ${admission.dailyLimit}',
          ),
          row(
            'Recent burst',
            '${admission.burstUsed} / ${admission.burstLimit}',
          ),
          const SizedBox(height: 6),
          Text(
            'No usage recorded yet — cloud stats appear here after a few turns.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ],
      );
    }
    final s = summarizeTurns(turns);
    final days = dailyUsage(turns);
    var inTok = 0, outTok = 0;
    final cloudSkills = <String, int>{};
    for (final t in turns) {
      final c = t['cost'];
      if (c is Map) {
        inTok += (c['in'] as num?)?.toInt() ?? 0;
        outTok += (c['out'] as num?)?.toInt() ?? 0;
        final sk = t['skill']?.toString();
        if (sk != null) cloudSkills[sk] = (cloudSkills[sk] ?? 0) + 1;
      }
    }
    String pct(int n) =>
        s.total == 0 ? '0%' : '${(100 * n / s.total).round()}%';
    final offline = s.total - s.paidCalls;
    final topCloud = cloudSkills.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          'Cloud admission today',
          '${admission.dailyUsed} / ${admission.dailyLimit}',
        ),
        row('Recent burst', '${admission.burstUsed} / ${admission.burstLimit}'),
        const SizedBox(height: 6),
        row('Turns', '${s.total}'),
        row('Ran offline (free)', '$offline  (${pct(offline)})'),
        row('Reached the cloud', '${s.paidCalls}  (${pct(s.paidCalls)})'),
        const SizedBox(height: 6),
        row('Estimated spend', '\$${s.spendUsd.toStringAsFixed(4)}'),
        if (s.activeDays > 0)
          row(
            '  ~ per day / month',
            '\$${s.spendPerDayUsd.toStringAsFixed(4)}  ·  ~\$${(s.spendPerDayUsd * 30).toStringAsFixed(2)}',
          ),
        row('Tokens (in / out)', '$inTok / $outTok'),
        if (s.byCloud.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Cloud health',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
          for (final e
              in (s.byCloud.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
            row('  ${e.key}', '${e.value}'),
        ],
        if (topCloud.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Where the cloud was used',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
          for (final e in topCloud.take(6)) row('  ${e.key}', '${e.value}'),
        ],
        const SizedBox(height: 8),
        Text('Recent days', style: TextStyle(fontSize: 12, color: cs.outline)),
        for (final d in days.take(7))
          row(
            '  ${d.date}',
            '${d.cloudCalls} cloud · \$${d.costUsd.toStringAsFixed(4)}',
          ),
        const SizedBox(height: 6),
        Text(
          'A green dot on a reply means it used the cloud; everything else ran on-device for free.',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
      ],
    );
  }

  /// Bundle every diagnostics .log from this device into one .txt and hand it to the platform share
  /// sheet — so a self-hosting user can email the file to themselves (and to me) with no cable. Caps
  /// the export to the most recent ~1 MB so it stays email-friendly. [_context] gives iPad/macOS the
  /// popover anchor the share sheet needs.
  Future<void> _shareLogs(BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);
    final box = ctx.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      if (!_diagnostics.allowsRawExport) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Raw diagnostics are disabled in this build.'),
          ),
        );
        return;
      }
      final dir = AppLog.instance.file.parent;
      final logs = dir.existsSync()
          ? (dir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.log'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path)))
          : <File>[];
      final package = await PackageInfo.fromPlatform();
      const revision = String.fromEnvironment(
        'PLENARA_REVISION',
        defaultValue: 'unversioned',
      );
      final includedFiles = logs.map((f) => f.uri.pathSegments.last).join(', ');
      final schemaVersions = <String>[];
      final types = Directory('${_cfg.dataDir}${Platform.pathSeparator}types');
      if (types.existsSync()) {
        for (final file in types.listSync().whereType<File>()) {
          try {
            final type =
                jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
            schemaVersions.add(
              '${type['typeId'] ?? type['id'] ?? file.uri.pathSegments.last}='
              '${type['schemaVersion'] ?? 1}',
            );
          } catch (_) {}
        }
        schemaVersions.sort();
      }
      final manifest = StringBuffer()
        ..writeln(
          '=== Plenara INTERNAL diagnostics export — ${DateTime.now()} ===',
        )
        ..writeln(
          'WARNING: contains conversation text, record values, and exception details.',
        )
        ..writeln('Build channel: ${_diagnostics.channel.name}')
        ..writeln('Revision: $revision')
        ..writeln('App version: ${package.version}+${package.buildNumber}')
        ..writeln(
          'Connection: ${_cfg.apiKey != null ? "cloud connected" : "offline"}',
        )
        ..writeln(
          'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        )
        ..writeln('Log files on device: ${logs.length}')
        ..writeln(
          'Included files: ${includedFiles.isEmpty ? "none" : includedFiles}',
        )
        ..writeln(
          'Schema versions: ${schemaVersions.isEmpty ? "none" : schemaVersions.join(", ")}',
        )
        ..writeln();
      final body = StringBuffer();
      for (final f in logs) {
        body.writeln('----- ${f.uri.pathSegments.last} -----');
        try {
          body.writeln(f.readAsStringSync());
        } catch (e) {
          body.writeln('(could not read: $e)');
        }
        body.writeln();
      }
      var trace = body.toString();
      const cap = 1024 * 1024; // keep the email small: most recent ~1 MB
      if (trace.length > cap) {
        trace =
            '[earlier logs truncated — showing the most recent ${cap ~/ 1024} KB]\n\n'
            '${trace.substring(trace.length - cap)}';
      }
      final text = '${manifest.toString()}$trace';
      final ts = DateTime.now().toIso8601String().replaceAll(
        RegExp('[:.]'),
        '-',
      );
      final out = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}plenara-diagnostics-$ts.txt',
      );
      out.writeAsStringSync(text);
      await Share.shareXFiles(
        [XFile(out.path, mimeType: 'text/plain')],
        subject: 'Plenara diagnostics',
        text: 'Plenara diagnostics log attached.',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share logs: $e')),
      );
    }
  }

  Widget _step(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$n. ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(text)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: cs.inversePrimary,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 76, 16),
              children: [
                const Text(
                  'Data folder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    key: const Key('data-location-status'),
                    avatar: Icon(
                      _cfg.dataFolderSelected
                          ? Icons.cloud_done_outlined
                          : Icons.phone_iphone,
                      size: 17,
                    ),
                    label: Text(
                      _cfg.dataFolderSelected
                          ? 'User-selected folder'
                          : 'Device-local only',
                    ),
                  ),
                ),
                SelectableText(_cfg.dataDir),
                const SizedBox(height: 6),
                Text(
                  _cfg.dataFolderSelected
                      ? 'Plenara watches this folder for changes from your sync provider.'
                      : 'Device-local data can be lost with the device. Choose an iCloud Drive, OneDrive, Google Drive, or other backed-up folder.',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('choose-data-folder'),
                    onPressed: _chooseDataFolder,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Choose data location'),
                  ),
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    const Text(
                      'Connect Claude',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      key: const Key('key-status'),
                      label: Text(
                        _cfg.apiKey != null ? 'connected ✓' : 'not connected',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Plenara uses your own Anthropic account, so your notes stay private and you pay Anthropic '
                  'directly — typically a few cents a month. It’s a one-time setup:',
                ),
                const SizedBox(height: 10),
                _step(
                  '1',
                  'Open the Anthropic Console (button below) and sign in or sign up.',
                ),
                _step(
                  '2',
                  'Under Billing, add a payment method — new accounts get free trial credits to start.',
                ),
                _step(
                  '3',
                  'Create an API key, then copy it (it’s shown only once).',
                ),
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
                SelectableText(
                  _keysUrl,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Paste your key (sk-ant-…)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Test connection'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _testing ? null : _save,
                      child: const Text('Save without testing'),
                    ),
                    const Spacer(),
                    if (_cfg.apiKey != null)
                      TextButton(
                        onPressed: _testing ? null : _disconnect,
                        style: TextButton.styleFrom(foregroundColor: cs.error),
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
                if (_statusMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _statusMsg!,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Your key is stored locally and only ever sent to Anthropic when a cloud feature runs. '
                  'Everything else works offline without it.',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                const Divider(height: 32),
                const Text(
                  'Motion',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  key: const Key('still-presence'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep Plena still'),
                  subtitle: const Text(
                    'Use a distinct static form for each state. This is independent of the system Reduce Motion setting.',
                  ),
                  value: _cfg.stillPresence,
                  onChanged: _setStillPresence,
                ),
                const Divider(height: 32),
                const Text(
                  'Mode',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  key: const Key('free-mode'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Free mode (offline only)'),
                  subtitle: const Text(
                    'Turns off every cloud feature — no Claude calls, no spend. Tasks, reminders, '
                    'people, logging and search all keep working on-device. Restart Plenara to apply.',
                  ),
                  value: _cfg.freeTier,
                  onChanged: (v) => _setFreeTier(v ?? false),
                ),
                CheckboxListTile(
                  key: const Key('confirm-spend'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Ask before paid builds'),
                  subtitle: const Text(
                    'Ask before anything that spends your Claude credits to BUILD something — a custom '
                    'tracker, or a movement routine and its drawings. Off by default: you already said '
                    'what you wanted. Everyday cloud use (understanding an unusual phrasing, gift '
                    'ideas, briefings) is not affected. Applies on next launch.',
                  ),
                  value: _cfg.confirmCloudSpend,
                  onChanged: (v) => _setConfirmSpend(v ?? false),
                ),
                const Divider(height: 32),
                const Text(
                  'Cloud usage',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                _usageSection(cs),
                _cloudContentSection(cs),
                const Divider(height: 32),
                const Text(
                  'Voice',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const VoiceUpgradeCard(), // iOS: the download nudge, or the voice picker; nothing off iOS
                const Divider(height: 32),
                const Text(
                  'Diagnostics log',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (_diagnostics.allowsRawExport) ...[
                  const Text(
                    'Internal diagnostics contain your conversation text, record values, and '
                    'exception details. Share them only when troubleshooting; the export is never '
                    'uploaded automatically.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(
                      builder: (btnCtx) => OutlinedButton.icon(
                        key: const Key('share-logs'),
                        onPressed: () => _shareLogs(btnCtx),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Share raw diagnostics'),
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'Diagnostics capture and raw export are disabled in this external build.',
                  ),
                const SizedBox(height: 8),
                if (_diagnostics.allowsRawExport)
                  SelectableText(
                    AppLog.instance.file.path,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
              ],
            ),
          ),
          const PlenaEmber(mode: 'Settings.'),
        ],
      ),
    );
  }
}
