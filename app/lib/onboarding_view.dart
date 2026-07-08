import 'package:flutter/material.dart';
import 'package:plenara/config.dart';

import 'settings_view.dart';

/// First-run welcome (task #14). Shown when no API key is set, so a new user is walked into the
/// guided Connect flow instead of having to discover it in Settings — but it never BLOCKS: the
/// offline features work without a key, so "Continue" always proceeds. Reuses [SettingsView] for
/// the actual connect. [configPath] is injectable for tests.
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final String? configPath;
  const WelcomeScreen({super.key, required this.onContinue, this.configPath});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool get _connected => loadConfig(configPath: widget.configPath).apiKey != null;

  Future<void> _openConnect() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsView(configPath: widget.configPath)),
    );
    if (mounted) setState(() {}); // reflect a key that may now be set
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = _connected;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(32),
            children: [
              Icon(Icons.spa, size: 56, color: cs.primary),
              const SizedBox(height: 16),
              Text('Welcome to Plenara',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'A private assistant that helps you show up for the people you love — remembering the '
                'little things, nudging you at the right moment, and keeping it all on your device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Icon(connected ? Icons.check_circle : Icons.auto_awesome,
                          color: connected ? Colors.green : cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          connected ? 'Claude is connected ✓' : 'Turn on the smart features',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                      'Briefings, gift ideas, and understanding what you type use your own Anthropic '
                      'account — it stays private and costs about a few cents a month. Everything else '
                      'works offline, so you can start right away and connect whenever you like.',
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              if (!connected)
                FilledButton.icon(
                  onPressed: _openConnect,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect Claude'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onContinue,
                child: Text(connected ? 'Continue to Plenara →' : 'Continue — I’ll connect later'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
