// Plenara v0 — Flutter desktop chat UI. A thin front-end over the v0 engine
// (package:plenara/session.dart): the interpreter, router, store, and cloud
// client are the same code the console uses. Text-first for now; voice later.
import 'package:flutter/material.dart';
import 'package:plenara/session.dart';

// The v0 seed data lives here (absolute so it resolves from the build dir).
const dataDir = r'Z:\code\plenara\v0\data';

void main() => runApp(const PlenaraApp());

class PlenaraApp extends StatelessWidget {
  const PlenaraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Plenara v0',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        home: const ChatScreen(),
      );
}

class Msg {
  final String text;
  final bool user;
  Msg(this.text, this.user);
}

class ChatScreen extends StatefulWidget {
  /// Tests inject a Session (temp data dir + replay/offline cloud) and set
  /// [retrieval] false; production leaves both defaulted.
  final Session? session;
  final bool retrieval;
  const ChatScreen({super.key, this.session, this.retrieval = true});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  late final Session _session = widget.session ?? Session(dataDir); // live wall clock
  final _msgs = <Msg>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _ready = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _session.init(retrieval: widget.retrieval);
      setState(() {
        _ready = true;
        _msgs.add(Msg(
            'Hi — I\'m Plenara. Try: "add call the plumber to my list", "log a 3k run", '
            '"remember that Mia is Sarah Mitchell\'s daughter", "what do I know about Mia", '
            '"list my tasks", or "start tracking my water intake". "undo that" reverses the last thing.',
            false));
      });
    } catch (e) {
      // no infinite spinner: surface the failure and let the user see it
      setState(() {
        _ready = true;
        _msgs.add(Msg("I couldn't start up — there may be a problem reading your data folder.\n\n$e", false));
      });
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(Msg(t, true));
      _busy = true;
    });
    _jump();
    String resp;
    try {
      resp = await _session.handle(t); // already catch-all internally; belt-and-suspenders here
    } catch (e) {
      resp = 'Something went wrong: $e';
    }
    // _busy is always cleared, so the input can never lock up
    setState(() {
      _msgs.add(Msg(resp, false));
      _busy = false;
    });
    _jump();
  }

  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Plenara'), backgroundColor: cs.inversePrimary),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (c, i) {
                    final m = _msgs[i];
                    return Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: m.user ? cs.primaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(m.text),
                      ),
                    );
                  },
                ),
              ),
              if (_busy) LinearProgressIndicator(minHeight: 2, color: cs.primary),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Say something…', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
                ]),
              ),
            ]),
    );
  }
}
