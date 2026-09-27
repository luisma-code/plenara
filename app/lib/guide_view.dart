import 'dart:async';
import 'package:flutter/material.dart';
import 'package:plenara/session.dart';
import 'package:plenara/guide.dart';
import 'plena.dart';
import 'plenara_theme.dart';
import 'speech.dart';
import 'speech_out.dart';
import 'voice_turn_controller.dart';
import 'undo_feedback.dart';
import 'guide_sources.dart';
import 'settings_view.dart';

/// Lives above Navigator so conversation access follows pushed detail pages.
class PlenaConnection extends ChangeNotifier {
  Session? session;
  VoiceTurnController? turn;
  bool conversationOpen = false;
  void setOpen(bool value) {
    conversationOpen = value;
    notifyListeners();
  }

  void attach(Session value, VoiceTurnController controller) {
    session = value;
    turn = controller;
    notifyListeners();
  }

  void detach(Session value) {
    if (identical(session, value)) {
      session = null;
      turn = null;
    }
  }
}

class PlenaHostScope extends InheritedWidget {
  final PlenaConnection connection;
  const PlenaHostScope({
    super.key,
    required this.connection,
    required super.child,
  });
  static PlenaConnection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlenaHostScope>()?.connection;
  @override
  bool updateShouldNotify(PlenaHostScope oldWidget) =>
      connection != oldWidget.connection;
}

class PlenaHostFrame extends StatefulWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  const PlenaHostFrame({
    super.key,
    required this.navigator,
    required this.child,
  });
  @override
  State<PlenaHostFrame> createState() => _PlenaHostFrameState();
}

class _PlenaHostFrameState extends State<PlenaHostFrame> {
  final connection = PlenaConnection();
  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }

  Future<void> _open(bool talk) async {
    final session = connection.session;
    final turn = connection.turn;
    if (session == null || turn == null || connection.conversationOpen) return;
    connection.setOpen(true);
    try {
      await widget.navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => GuideConversationView(
            session: session,
            turn: turn,
            startListening: talk,
          ),
        ),
      );
    } finally {
      if (mounted) connection.setOpen(false);
    }
  }

  @override
  Widget build(BuildContext context) => PlenaHostScope(
    connection: connection,
    child: ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final visible =
            connection.session != null && !connection.conversationOpen;
        return LayoutBuilder(
          builder: (context, constraints) {
            final tablet = constraints.maxWidth >= 840;
            return Column(
              children: [
                Expanded(child: widget.child),
                if (visible)
                  tablet
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: 520,
                            child: PlenaAccessBar(
                              onTalk: () => _open(true),
                              onMessage: () => _open(false),
                            ),
                          ),
                        )
                      : PlenaAccessBar(
                          onTalk: () => _open(true),
                          onMessage: () => _open(false),
                        ),
              ],
            );
          },
        );
      },
    ),
  );
}

class PlenaAccessBar extends StatelessWidget {
  final VoidCallback onTalk;
  final VoidCallback onMessage;
  const PlenaAccessBar({
    super.key,
    required this.onTalk,
    required this.onMessage,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: PlenaraTheme.ground,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const Key('talk-to-plena'),
              onPressed: onTalk,
              icon: const Icon(Icons.mic_none_rounded),
              label: const Text('Talk to Plena'),
            ),
            OutlinedButton.icon(
              key: const Key('message-plena'),
              onPressed: onMessage,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Message Plena'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shared by roots and details in standalone widget/test hosts as well.
Future<void> openPlenaConversation(
  BuildContext context,
  Session session, {
  VoiceTurnController? turn,
  String? focusId,
  String? seed,
  bool talk = false,
}) async {
  final connection = PlenaHostScope.maybeOf(context);
  if (connection?.conversationOpen == true) return;
  final shared = turn ?? connection?.turn;
  connection?.setOpen(true);
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuideConversationView(
          session: session,
          turn: shared,
          focusId: focusId,
          seed: seed,
          startListening: talk,
        ),
      ),
    );
  } finally {
    connection?.setOpen(false);
  }
}

class GuideConversationView extends StatefulWidget {
  final Session session;
  final VoiceTurnController? turn;
  final String? focusId;
  final String? seed;
  final bool startListening;
  const GuideConversationView({
    super.key,
    required this.session,
    this.turn,
    this.focusId,
    this.seed,
    this.startListening = false,
  });
  @override
  State<GuideConversationView> createState() => _GuideConversationViewState();
}

class _GuideConversationViewState extends State<GuideConversationView>
    with WidgetsBindingObserver {
  late final VoiceTurnController turn =
      widget.turn ??
      VoiceTurnController(
        runTurn: (u) async =>
            TurnOutcome(response: await widget.session.converse(u)),
        navCommand: (_) => false,
        onTurnStarting: () {},
        onTurnPresented: (_) {},
        syncRoutineCadence: () {},
        onCaptureResolved: () {},
        log: (_) {},
        logDebug: (_) {},
        persistMicHints: (_) {},
        persistMute: (_) {},
      );
  final _scroll = ScrollController();
  String? _previousFocus;
  String? _notice;
  bool _applying = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previousFocus = widget.session.guideFocusId;
    if (widget.focusId != null) widget.session.guideFocusId = widget.focusId;
    turn.addListener(_changed);
    if (widget.turn == null) {
      turn.speech = NoopSpeechRecognizer();
      turn.voice = NoopSpeechOutput();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.seed != null) turn.input.text = widget.seed!;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      if (widget.startListening) {
        if (turn.speech?.available == true) {
          turn.toggleMic();
        } else {
          setState(
            () => _notice =
                'Microphone unavailable. You can message Plena below.',
          );
        }
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      turn.abandonForBackground(
        'Listening stopped when the app went to the background.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    turn.removeListener(_changed);
    turn.cancelListening();
    turn.voice?.stop();
    if (widget.turn == null) turn.dispose();
    widget.session.guideFocusId = _previousFocus;
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final result = await widget.session.applyGuideReceipt();
    if (!mounted) return;
    setState(() {
      _applying = false;
      _notice = result.message;
    });
    showUndoableResult(
      context,
      message: result.message,
      onUndo: result.undoId == null
          ? null
          : () => widget.session.undoById(result.undoId!),
    );
  }

  Future<void> _edit(int index) async {
    final receipt = widget.session.guideReceipt!;
    final change = receipt.changes[index];
    final fields = Map<String, dynamic>.from(change['fields'] as Map);
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReceiptEditor(
        fields: fields,
        type: widget.session.types[change['type']]!,
        records: widget.session.store,
      ),
    );
    if (updated != null) {
      await widget.session.editGuideReceipt(index, updated);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.session.conversationLedger.entries;
    final receipt = widget.session.guideReceipt;
    final focus = widget.session.store[widget.session.guideFocusId];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plena'),
        actions: [
          IconButton(
            tooltip: 'Guide settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsView(guideSession: widget.session),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bring selected context',
            icon: const Icon(Icons.add_link),
            onPressed: () async {
              final draft = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => GuideSourcesView(session: widget.session),
                ),
              );
              if (draft != null && mounted) turn.input.text = draft;
            },
          ),
          IconButton(
            tooltip: turn.voiceMuted ? 'Unmute replies' : 'Mute replies',
            onPressed: turn.toggleMute,
            icon: Icon(
              turn.voiceMuted
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (focus != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'About ${focus['displayName'] ?? focus['description'] ?? focus['title'] ?? 'this record'}',
                style: const TextStyle(color: PlenaraTheme.quietInk),
              ),
            ),
          Expanded(
            child: ListView(
              key: const Key('plena-conversation'),
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (entries.isEmpty)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'What would make today feel worthwhile? Tell me what is on your mind, or something that happened.',
                        ),
                      ),
                    ),
                  ),
                for (final entry in entries) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .76,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(entry.utterance),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 22),
                        child: SelectableText(entry.reply),
                      ),
                    ),
                  ),
                ],
                if (turn.listening || turn.transcribing || turn.busy)
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: PresenceView(
                          state: turn.listening
                              ? PresenceState.listening
                              : PresenceState.thinking,
                          animate: false,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          turn.listening
                              ? 'Listening — tap Finish to send. ${turn.caption ?? ''}'
                              : turn.transcribing
                              ? 'Finishing your transcript…'
                              : 'Plena is thinking…',
                        ),
                      ),
                    ],
                  ),
                if (receipt != null)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Card(
                        key: const Key('guide-receipt'),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                receipt.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Text(
                                'Proposed updates · nothing applied yet',
                                style: TextStyle(color: PlenaraTheme.quietInk),
                              ),
                              for (final (index, change)
                                  in receipt.changes.indexed)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${change['operation'] == 'create' ? 'Add' : 'Update'} ${_recordLabel(change)}',
                                  ),
                                  subtitle: Text(
                                    '${change['reason']}\n${_fieldsSummary(change['fields'] as Map, widget.session, receipt)}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit update',
                                        onPressed: () => _edit(index),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove update',
                                        onPressed: () async {
                                          await widget.session
                                              .removeGuideReceiptChange(index);
                                          if (mounted) setState(() {});
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: _applying ? null : _apply,
                                    child: const Text('Apply updates'),
                                  ),
                                  TextButton(
                                    onPressed: _applying
                                        ? null
                                        : () async {
                                            await widget.session
                                                .dismissGuideReceipt();
                                            if (mounted) setState(() {});
                                          },
                                    child: const Text('Dismiss'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_notice!),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (turn.listening)
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: turn.toggleMic,
                              child: const Text('Finish and send'),
                            ),
                            TextButton(
                              onPressed: turn.cancelListening,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('plena-message-input'),
                              controller: turn.input,
                              minLines: 1,
                              maxLines: 4,
                              onSubmitted: (_) => turn.send(),
                              decoration: const InputDecoration(
                                hintText: 'Message Plena…',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Send message',
                            onPressed: turn.busy ? null : turn.send,
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                      if (!turn.listening)
                        TextButton.icon(
                          onPressed: turn.busy
                              ? null
                              : () {
                                  if (turn.speech?.available == true) {
                                    turn.toggleMic();
                                  } else {
                                    setState(
                                      () => _notice =
                                          'Microphone unavailable. Messaging remains available.',
                                    );
                                  }
                                },
                          icon: const Icon(Icons.mic_none_rounded),
                          label: const Text('Talk to Plena'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fieldLabel(String value) =>
    value.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
String _fieldsSummary(Map fields, Session session, GuideReceipt receipt) {
  String display(dynamic value) {
    if (value is List) return value.map(display).join(', ');
    final record = session.store[value];
    if (record != null) {
      return '${record['displayName'] ?? record['title'] ?? record['description'] ?? value}';
    }
    for (final change in receipt.changes) {
      if (change['id'] == value) return _recordLabel(change);
    }
    return '$value';
  }

  return fields.entries
      .where(
        (e) => !const {
          'id',
          'createdAt',
          'title',
          'description',
          'displayName',
        }.contains(e.key),
      )
      .map((e) => '${_fieldLabel('${e.key}')}: ${display(e.value)}')
      .join('\n');
}

String _recordLabel(Map change) {
  final f = change['fields'] as Map;
  return '${f['title'] ?? f['description'] ?? f['displayName'] ?? change['type']}';
}

class _ReceiptEditor extends StatefulWidget {
  final Map<String, dynamic> fields, type;
  final Map<String, Map<String, dynamic>> records;
  const _ReceiptEditor({
    required this.fields,
    required this.type,
    required this.records,
  });
  @override
  State<_ReceiptEditor> createState() => _ReceiptEditorState();
}

class _ReceiptEditorState extends State<_ReceiptEditor> {
  late final fields = Map<String, dynamic>.from(widget.fields);
  late final attributes = {
    for (final a in (widget.type['attributes'] as List).whereType<Map>())
      '${a['name']}': a,
  };
  late final controllers = {
    for (final e in fields.entries)
      if (attributes[e.key]?['valueType'] != 'entityRef' &&
          attributes[e.key]?['valueType'] != 'boolean' &&
          attributes[e.key]?['valueType'] != 'enum' &&
          (e.value is String || e.value is num))
        e.key: TextEditingController(text: '${e.value}'),
  };
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit proposed update'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in fields.entries)
            if (controllers.containsKey(e.key))
              TextField(
                controller: controllers[e.key],
                decoration: InputDecoration(labelText: _fieldLabel(e.key)),
                maxLines: const {'note', 'notes', 'instruction'}.contains(e.key)
                    ? 3
                    : 1,
              )
            else if (attributes[e.key]?['valueType'] == 'boolean')
              CheckboxListTile(
                title: Text(_fieldLabel(e.key)),
                value: fields[e.key] == true,
                onChanged: (v) => setState(() => fields[e.key] = v),
              )
            else if (attributes[e.key]?['valueType'] == 'enum')
              DropdownButtonFormField<String>(
                initialValue: '${fields[e.key]}',
                decoration: InputDecoration(labelText: _fieldLabel(e.key)),
                items: [
                  for (final value in attributes[e.key]!['enumValues'] as List)
                    DropdownMenuItem(value: '$value', child: Text('$value')),
                ],
                onChanged: (v) => setState(() => fields[e.key] = v),
              )
            else if (attributes[e.key]?['valueType'] == 'entityRef')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${_fieldLabel(e.key)}: ${_referenceLabel(e.value)}',
                ),
              ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          for (final e in controllers.entries) {
            fields[e.key] = widget.fields[e.key] is num
                ? num.tryParse(e.value.text)
                : e.value.text;
          }
          Navigator.pop(context, fields);
        },
        child: const Text('Update proposal'),
      ),
    ],
  );
  String _referenceLabel(dynamic value) {
    if (value is List) return value.map(_referenceLabel).join(', ');
    final record = widget.records[value];
    return record == null
        ? 'Another proposed item'
        : '${record['displayName'] ?? record['title'] ?? record['description'] ?? 'Selected record'}';
  }
}
