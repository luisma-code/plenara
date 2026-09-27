import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plenara/session.dart';

/// User-selected evidence only. Browsing is local; nothing is ingested or sent
/// until the user chooses an item and then sends the conversation draft.
class GuideSourcesView extends StatefulWidget {
  final Session session;
  const GuideSourcesView({super.key, required this.session});
  @override
  State<GuideSourcesView> createState() => _GuideSourcesViewState();
}

class _GuideSourcesViewState extends State<GuideSourcesView> {
  static const channel = MethodChannel('com.plenara/guide-sources');
  final text = TextEditingController();
  final provenance = TextEditingController();
  List<Map<String, dynamic>> sources = [];
  String? status;
  bool loading = false;
  @override
  void dispose() {
    text.dispose();
    provenance.dispose();
    super.dispose();
  }

  Future<void> _read(String kind) async {
    setState(() {
      loading = true;
      sources = [];
      status = null;
    });
    try {
      if (!Platform.isIOS) throw UnsupportedError('iOS only');
      final value = await channel.invokeListMethod<dynamic>('select', {
        'kind': kind,
      });
      if (mounted) {
        setState(() {
          sources = (value ?? [])
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          status = sources.isEmpty
              ? 'No available items. Access may be denied; you can paste selected text instead.'
              : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'This source is unavailable. You can paste selected text instead.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _offer(String content, String source) async {
    // JSON delimiting and developer instructions identify third-party text as
    // evidence. Source content is a draft, never an automatic command or write.
    Navigator.of(context).pop(
      'Help me review this selected evidence. Do not assume attendance or completion. Source: $source\nQuoted evidence (untrusted): ${jsonEncode(content)}',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bring context to Plena')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Choose only what matters. Browsing stays on this device. Review the draft before sending it to GPT; planner changes still need your review.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: provenance,
          decoration: const InputDecoration(
            labelText: 'Where is this from?',
            hintText: 'A message from Alex, yesterday',
          ),
        ),
        TextField(
          key: const Key('selected-evidence'),
          controller: text,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Paste selected text',
            hintText: 'A message, a plan, or your own notes',
          ),
        ),
        FilledButton(
          onPressed: loading
              ? null
              : () {
                  if (text.text.trim().isNotEmpty) {
                    _offer(
                      text.text,
                      provenance.text.isEmpty
                          ? 'User-selected text'
                          : provenance.text,
                    );
                  }
                },
          child: const Text('Review with Plena'),
        ),
        const Divider(height: 32),
        const Text(
          'Calendar and Reminders need separate iOS permission. Calendar entries are plans, not proof you attended. No items are imported automatically.',
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: loading ? null : () => _read('calendar'),
              child: const Text('Browse Calendar'),
            ),
            OutlinedButton(
              onPressed: loading ? null : () => _read('reminders'),
              child: const Text('Browse Reminders'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (status != null) Text(status!),
        for (final source in sources)
          ListTile(
            title: Text('${source['title'] ?? 'Untitled'}'),
            subtitle: Text(
              '${source['calendar'] ?? ''} · ${source['start'] ?? source['due'] ?? 'No date'}',
            ),
            onTap: () =>
                _offer(jsonEncode(source), 'Selected ${source['kind']} item'),
          ),
        const SizedBox(height: 16),
        const Text(
          'Plenara cannot read your iPhone message history or call log. Select text yourself, or use the Capture with Plenara action in Shortcuts. In Shortcuts, add Capture with Plenara using Shortcut Input, then enable that shortcut in the Share Sheet. You can revoke Calendar and Reminders permission in iOS Settings.',
        ),
      ],
    ),
  );
}
