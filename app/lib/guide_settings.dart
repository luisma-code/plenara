import 'dart:io';
import 'package:flutter/material.dart';
import 'package:plenara/config.dart';
import 'package:plenara/guide.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';
import 'credential_store.dart';

class GuideSettingsCard extends StatefulWidget {
  final Session? session;
  final String? configPath;
  const GuideSettingsCard({super.key, this.session, this.configPath});
  @override
  State<GuideSettingsCard> createState() => _GuideSettingsCardState();
}

class _GuideSettingsCardState extends State<GuideSettingsCard> {
  final keyInput = TextEditingController();
  late final limitInput = TextEditingController(
    text: '${loadConfig(configPath: widget.configPath).guideMonthlyLimit}',
  );
  bool consent = false, saving = false;
  String? status;
  @override
  void dispose() {
    keyInput.dispose();
    limitInput.dispose();
    super.dispose();
  }

  void _applyClient(double limit) {
    final cfg = loadConfig(configPath: widget.configPath);
    final storage = widget.session?.repo;
    if (activeGuideKey != null && storage is FileStorageRepository) {
      storage.registerTurnlogSecret(activeGuideKey!);
    }
    widget.session?.guide = cfg.freeTier
        ? const OfflineGuide()
        : OpenAiGuide(
            key: activeGuideKey,
            budget: GuideBudget(
              '${widget.configPath == null ? defaultDeviceDir() : File(widget.configPath!).parent.path}/guide-usage.json',
              limit,
            ),
          );
  }

  Future<void> _save() async {
    final limit = double.tryParse(limitInput.text);
    if (limit == null || !limit.isFinite || limit < 0) {
      setState(() => status = 'Enter a monthly limit of zero or more dollars.');
      return;
    }
    if (limit > 0 && !consent) {
      setState(
        () => status =
            'Choose whether to send conversation context to OpenAI first.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (keyInput.text.trim().isNotEmpty) {
        await saveGuideCredential(keyInput.text);
      }
      saveConfig(guideMonthlyLimit: limit, configPath: widget.configPath);
      _applyClient(limit);
      keyInput.clear();
      if (mounted) {
        setState(
          () => status = limit == 0
              ? 'GPT is paused. Local actions remain available.'
              : activeGuideKey == null
              ? 'Limit saved. Add an OpenAI API key to connect the guide.'
              : loadConfig(configPath: widget.configPath).freeTier
              ? 'Settings saved. Free mode keeps GPT paused.'
              : 'Plena guide connected.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'Secure storage could not verify the key. GPT was not connected by this change.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.session?.guide;
    final usage = client is OpenAiGuide ? client.budget.snapshot : null;
    return Card(
      key: const Key('guide-settings'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plena guide', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'A continuing conversation with GPT, grounded in your people, tasks and routines. OpenAI API billing is separate from ChatGPT and Codex.',
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('guide-api-key'),
              controller: keyInput,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: activeGuideKey == null
                    ? 'OpenAI API key'
                    : 'Replace OpenAI API key',
                helperText:
                    'Stored in this device’s secure keychain. Never synced.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('guide-monthly-limit'),
              controller: limitInput,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monthly limit in USD',
                helperText:
                    'Zero pauses GPT. Each request reserves its full possible cost first.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: saving
                  ? null
                  : (v) => setState(() => consent = v ?? false),
              title: const Text('Use OpenAI for conversations I send'),
              subtitle: const Text(
                'Sends recent Plena dialogue and relevant people, facts, interactions, tasks, reminders, practices and guided routines. Journal, mood records, contact phone/email fields, and diagnostics are excluded. Imported text is sent only when you choose to send it. API processing may retain abuse-monitoring logs; store:false does not mean zero retention.',
              ),
            ),
            const Text(
              'GPT-6 Sol: \$2 per million input tokens and \$10 per million output tokens. A 5,000-input / 1,000-output request is about \$0.02; tool calls can require several requests. This is an estimate, not a monthly usage prediction.',
            ),
            if (usage != null)
              Text(
                usage['unavailable'] == true
                    ? 'Usage state needs repair; requests are blocked.'
                    : 'This month: \$${(usage['spent'] as num).toStringAsFixed(3)} used, \$${(usage['reserved'] as num).toStringAsFixed(3)} reserved.',
              ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: const Text('Save guide settings'),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          await saveGuideCredential('');
                          saveConfig(
                            guideMonthlyLimit: 0,
                            configPath: widget.configPath,
                          );
                          _applyClient(0);
                          if (mounted) {
                            setState(() => status = 'GPT disconnected.');
                          }
                        },
                  child: const Text('Disconnect GPT'),
                ),
              ],
            ),
            if (status != null) Text(status!),
          ],
        ),
      ),
    );
  }
}
