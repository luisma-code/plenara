import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/turnlog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
    // url_launcher hands the URL to the OS on every platform — critically including iOS, where the
    // old Process.run('open'/'xdg-open') path is forbidden in the sandbox (it silently no-op'd, so
    // the button "did nothing"). externalApplication forces the system browser, not an in-app view.
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* the URL is also shown as copyable text as a fallback */}
  }

  Future<CloudResult<String>> _defaultValidate(String key) => ClaudeClient(apiKeyOverride: key).validateKey();

  /// Persist a key + refresh state. Clears the field only if it still holds the SAME key we saved
  /// (so a key typed while a test was in flight isn't wiped — Fable review).
  void _persist(String key) {
    saveConfig(dataDir: _cfg.dataDir, apiKey: key, configPath: widget.configPath);
    _cfg = loadConfig(configPath: widget.configPath);
    if (_keyCtrl.text.trim() == key) _keyCtrl.clear();
  }

  void _save() {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      // Don't claim "Saved" while silently changing nothing — empty means "use Disconnect".
      setState(() {
        _statusMsg = 'Paste a key first — or use Disconnect to remove your key.';
        _statusColor = Colors.orange;
      });
      return;
    }
    setState(() {
      _persist(key);
      _statusMsg = 'Saved — restart Plenara to apply.';
      _statusColor = null;
    });
  }

  /// Toggle free (offline-only) mode. Persisted now; applied on next launch (like the key),
  /// since the Session is built once at startup.
  void _setFreeTier(bool value) {
    saveConfig(dataDir: _cfg.dataDir, freeTier: value, configPath: widget.configPath);
    setState(() {
      _cfg = loadConfig(configPath: widget.configPath);
      _statusMsg = value
          ? 'Free mode on — restart Plenara to run fully offline.'
          : 'Paid mode on — restart Plenara to re-enable cloud features.';
      _statusColor = null;
    });
  }

  /// Explicitly remove the key ('' clears; null would leave it untouched).
  void _disconnect() {
    saveConfig(dataDir: _cfg.dataDir, apiKey: '', configPath: widget.configPath);
    setState(() {
      _cfg = loadConfig(configPath: widget.configPath);
      _keyCtrl.clear();
      _statusMsg = 'Disconnected. Offline features still work.';
      _statusColor = null;
    });
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
        _persist(key);
        _statusMsg = "Connected ✓ — your key works and it's saved. Restart Plenara to apply.";
        _statusColor = Colors.green;
      } else if (res is CloudError<String>) {
        // A no-credits key AUTHENTICATED — it's valid, so save it (billing is the only gap). The
        // key is shown only once; discarding it would force the user to mint a new one after they
        // add billing (Fable review).
        if (res.kind == CloudErrorKind.insufficientCredits) _persist(key);
        _statusMsg = _friendly(res.kind);
        _statusColor = res.kind == CloudErrorKind.insufficientCredits ? Colors.orange : Colors.red;
      }
    });
  }

  String _friendly(CloudErrorKind k) => switch (k) {
        CloudErrorKind.badKey =>
          'That key was rejected. Recopy the whole key (it starts with “sk-ant-”) — it’s shown only once, so create a fresh one if needed.',
        CloudErrorKind.insufficientCredits =>
          'Saved your key — it works. But your Anthropic account has no credits yet: in the Console, open Billing → add a payment method (new accounts get free trial credits), then you’re all set.',
        CloudErrorKind.offline => "Couldn't reach Anthropic — check your internet connection and try again.",
        CloudErrorKind.timeout => "Anthropic didn't respond in time — try again.",
        CloudErrorKind.rateLimited => 'Rate-limited right now — wait a moment and Test again.',
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
    if (turns.isEmpty) {
      return Text('No usage recorded yet — cloud stats appear here after a few turns.',
          style: TextStyle(fontSize: 12, color: cs.outline));
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
    String pct(int n) => s.total == 0 ? '0%' : '${(100 * n / s.total).round()}%';
    final offline = s.total - s.paidCalls;
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(a, style: const TextStyle(fontSize: 13)),
            Text(b, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
    final topCloud = cloudSkills.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('Turns', '${s.total}'),
      row('Ran offline (free)', '$offline  (${pct(offline)})'),
      row('Reached the cloud', '${s.paidCalls}  (${pct(s.paidCalls)})'),
      const SizedBox(height: 6),
      row('Estimated spend', '\$${s.spendUsd.toStringAsFixed(4)}'),
      if (s.activeDays > 0)
        row('  ~ per day / month',
            '\$${s.spendPerDayUsd.toStringAsFixed(4)}  ·  ~\$${(s.spendPerDayUsd * 30).toStringAsFixed(2)}'),
      row('Tokens (in / out)', '$inTok / $outTok'),
      if (s.byCloud.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Cloud health', style: TextStyle(fontSize: 12, color: cs.outline)),
        for (final e in (s.byCloud.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          row('  ${e.key}', '${e.value}'),
      ],
      if (topCloud.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Where the cloud was used', style: TextStyle(fontSize: 12, color: cs.outline)),
        for (final e in topCloud.take(6)) row('  ${e.key}', '${e.value}'),
      ],
      const SizedBox(height: 8),
      Text('Recent days', style: TextStyle(fontSize: 12, color: cs.outline)),
      for (final d in days.take(7))
        row('  ${d.date}', '${d.cloudCalls} cloud · \$${d.costUsd.toStringAsFixed(4)}'),
      const SizedBox(height: 6),
      Text('A green dot on a reply means it used the cloud; everything else ran on-device for free.',
          style: TextStyle(fontSize: 12, color: cs.outline)),
    ]);
  }

  /// Bundle every diagnostics .log from this device into one .txt and hand it to the platform share
  /// sheet — so a self-hosting user can email the file to themselves (and to me) with no cable. Caps
  /// the export to the most recent ~1 MB so it stays email-friendly. [_context] gives iPad/macOS the
  /// popover anchor the share sheet needs.
  Future<void> _shareLogs(BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);
    try {
      final dir = AppLog.instance.file.parent;
      final logs = dir.existsSync()
          ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.log')).toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          : <File>[];
      final buf = StringBuffer()
        ..writeln('=== Plenara diagnostics export — ${DateTime.now()} ===')
        ..writeln('App version: ${_cfg.apiKey != null ? "cloud connected" : "offline"}')
        ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('Log files on device: ${logs.length}')
        ..writeln();
      for (final f in logs) {
        buf.writeln('----- ${f.uri.pathSegments.last} -----');
        try {
          buf.writeln(f.readAsStringSync());
        } catch (e) {
          buf.writeln('(could not read: $e)');
        }
        buf.writeln();
      }
      var text = buf.toString();
      const cap = 1024 * 1024; // keep the email small: most recent ~1 MB
      if (text.length > cap) {
        text = '[earlier logs truncated — showing the most recent ${cap ~/ 1024} KB]\n\n'
            '${text.substring(text.length - cap)}';
      }
      final ts = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
      final out = File('${Directory.systemTemp.path}${Platform.pathSeparator}plenara-diagnostics-$ts.txt');
      out.writeAsStringSync(text);
      final box = ctx.findRenderObject() as RenderBox?;
      final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
      await Share.shareXFiles(
        [XFile(out.path, mimeType: 'text/plain')],
        subject: 'Plenara diagnostics',
        text: 'Plenara diagnostics log attached.',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share logs: $e')));
    }
  }

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
            TextButton(onPressed: _testing ? null : _save, child: const Text('Save without testing')),
            const Spacer(),
            if (_cfg.apiKey != null)
              TextButton(
                onPressed: _testing ? null : _disconnect,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: const Text('Disconnect'),
              ),
          ]),
          if (_statusMsg != null) ...[
            const SizedBox(height: 10),
            Text(_statusMsg!, style: TextStyle(color: _statusColor, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 8),
          Text('Your key is stored locally and only ever sent to Anthropic when a cloud feature runs. '
              'Everything else works offline without it.', style: TextStyle(fontSize: 12, color: cs.outline)),
          const Divider(height: 32),
          const Text('Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          CheckboxListTile(
            key: const Key('free-mode'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Free mode (offline only)'),
            subtitle: const Text('Turns off every cloud feature — no Claude calls, no spend. Tasks, reminders, '
                'people, logging and search all keep working on-device. Restart Plenara to apply.'),
            value: _cfg.freeTier,
            onChanged: (v) => _setFreeTier(v ?? false),
          ),
          const Divider(height: 32),
          const Text('Cloud usage', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _usageSection(cs),
          const Divider(height: 32),
          const Text('Diagnostics log', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('If something goes wrong, share the log so it can be troubleshot — this bundles '
              'every log on this device into one text file and opens the share sheet (email it to '
              'yourself).'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (btnCtx) => OutlinedButton.icon(
                key: const Key('share-logs'),
                onPressed: () => _shareLogs(btnCtx),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share diagnostics'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(AppLog.instance.file.path, style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ),
    );
  }
}
