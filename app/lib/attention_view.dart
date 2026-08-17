import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';

import 'presence_shell.dart';

class AttentionView extends StatefulWidget {
  final Session session;
  final VoidCallback? onChanged;

  const AttentionView({super.key, required this.session, this.onChanged});

  @override
  State<AttentionView> createState() => _AttentionViewState();
}

class _AttentionViewState extends State<AttentionView> {
  String? _message;

  String _value(Object? value) {
    if (value is Map || value is List) return jsonEncode(value);
    return value == null ? '(empty)' : '$value';
  }

  String _filePreview(String path) {
    try {
      final text = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(File(path).readAsStringSync()));
      return text.length > 1200 ? '${text.substring(0, 1200)}…' : text;
    } catch (_) {
      return '(could not read this version)';
    }
  }

  void _resolveRecord(Map<String, dynamic> conflict, bool restoreOther) {
    final ok = widget.session.resolveRecordSyncConflict(
      conflict,
      restoreOther: restoreOther,
    );
    setState(() {
      _message = ok
          ? 'Conflict resolved. The change is saved and undoable.'
          : 'That conflict could not be resolved safely.';
    });
    widget.onChanged?.call();
  }

  void _resolveDefinition(DefinitionConflict conflict, bool useOther) {
    final ok = widget.session.resolveDefinitionSyncConflict(
      conflict,
      useConflicting: useOther,
    );
    setState(() {
      _message = ok
          ? 'Definition choice saved. Restart Plenara to activate it.'
          : 'That definition could not be resolved safely.';
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.session.recordSyncConflicts;
    final definitions = widget.session.definitionSyncConflicts;
    final other = widget.session.repairIssues.where((issue) {
      return !issue.contains('sync conflict');
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Needs attention')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 76, 32),
            children: [
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_message!, key: const Key('attention-message')),
                ),
              if (records.isEmpty && definitions.isEmpty && other.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Everything is in order'),
                  ),
                ),
              for (final conflict in records)
                _RecordConflictCard(
                  conflict: conflict,
                  current: widget
                      .session
                      .store['${conflict['recordId']}']?['${conflict['field']}'],
                  valueText: _value,
                  onKeep: () => _resolveRecord(conflict, false),
                  onRestore: () => _resolveRecord(conflict, true),
                ),
              for (final conflict in definitions)
                _DefinitionConflictCard(
                  conflict: conflict,
                  current: _filePreview(conflict.canonicalPath),
                  other: _filePreview(conflict.conflictingPath),
                  onKeep: () => _resolveDefinition(conflict, false),
                  onUseOther: () => _resolveDefinition(conflict, true),
                ),
              for (final issue in other)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(issue),
                  ),
                ),
            ],
          ),
          const PlenaEmber(mode: 'Repair.'),
        ],
      ),
    );
  }
}

class _RecordConflictCard extends StatelessWidget {
  final Map<String, dynamic> conflict;
  final Object? current;
  final String Function(Object?) valueText;
  final VoidCallback onKeep;
  final VoidCallback onRestore;

  const _RecordConflictCard({
    required this.conflict,
    required this.current,
    required this.valueText,
    required this.onKeep,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey(
      'record-conflict-${conflict['recordId']}-${conflict['field']}',
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Two devices edited ${conflict['field']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('Current: ${valueText(current)}'),
          const SizedBox(height: 6),
          Text('Other version: ${valueText(conflict['value'])}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: onKeep,
                child: const Text('Keep current'),
              ),
              OutlinedButton(
                onPressed: onRestore,
                child: const Text('Restore other'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DefinitionConflictCard extends StatelessWidget {
  final DefinitionConflict conflict;
  final String current;
  final String other;
  final VoidCallback onKeep;
  final VoidCallback onUseOther;

  const _DefinitionConflictCard({
    required this.conflict,
    required this.current,
    required this.other,
    required this.onKeep,
    required this.onUseOther,
  });

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('definition-conflict-${conflict.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Two versions of ${conflict.id}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('Current', style: Theme.of(context).textTheme.labelLarge),
          SelectableText(current),
          const Divider(height: 24),
          Text('Other version', style: Theme.of(context).textTheme.labelLarge),
          SelectableText(other),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: onKeep,
                child: const Text('Keep current'),
              ),
              OutlinedButton(
                onPressed: onUseOther,
                child: const Text('Use other version'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
