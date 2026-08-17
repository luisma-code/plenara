import 'package:flutter/material.dart';
import 'package:plenara/config.dart';

import 'credential_store.dart';
import 'plena.dart';
import 'plenara_theme.dart';
import 'settings_view.dart';

/// Welcome / connect nudge (task #14). Shown whenever no API key is set — i.e. on first run AND on
/// later launches until the user connects — so the guided Connect flow is one tap away instead of
/// buried in Settings. It never BLOCKS: offline features work without a key, so "Continue" always
/// proceeds into the app. (If the recurring nudge is unwanted, persist a "dismissed" flag; today
/// it re-appears until connected by design.) Reuses [SettingsView]. [configPath] is test-injectable.
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final String? configPath;
  const WelcomeScreen({super.key, required this.onContinue, this.configPath});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Load once (loadConfig reads — and on first run WRITES — the config file; doing it in build()
  // would be filesystem I/O on every frame). Refresh only after returning from Connect.
  late PlenaraConfig _cfg = loadAppConfig(configPath: widget.configPath);
  bool get _connected => _cfg.apiKey != null;

  Future<void> _openConnect() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsView(configPath: widget.configPath),
      ),
    );
    if (mounted) {
      setState(() => _cfg = loadAppConfig(configPath: widget.configPath));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = _connected;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 170,
                            child: Semantics(
                              image: true,
                              label: 'Plena, a warm constellation of light',
                              child: const PresenceView(
                                animate: false,
                                state: PresenceState.idle,
                              ),
                            ),
                          ),
                          Text(
                            'Meet Plena',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: -.4,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'A living planner that helps you remember what matters and show up for the people you love.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: PlenaraTheme.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: PlenaraTheme.line),
                            ),
                            padding: const EdgeInsets.all(11),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  connected
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.lock_outline_rounded,
                                  color: connected
                                      ? const Color(0xFF9FC59E)
                                      : cs.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    connected
                                        ? 'Claude is connected. Your key stays in secure system storage.'
                                        : 'Your records stay in your data folder. This internal build keeps conversation diagnostics on this device unless you explicitly share them.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: PlenaraTheme.quietInk,
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (!connected)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openConnect,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Connect Claude'),
                      ),
                    )
                  else
                    const Text(
                      'Claude is connected ✓',
                      style: TextStyle(color: Color(0xFF9FC59E)),
                    ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: widget.onContinue,
                      child: Text(
                        connected
                            ? 'Continue to Today'
                            : 'Continue offline for now',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
