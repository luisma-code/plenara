import 'dart:io';
import 'package:plenara/session.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';

// Each case: a fresh seeded folder, optional setup turns, then the probe utterance.
// Prints the response + the records it produced so we can eyeball correctness.
Future<void> run(String label, List<String> setup, String probe, String key) async {
  final dir = Directory.systemTemp.createTempSync('uc_').path;
  ensureSeeded(dir, r'Z:\code\plenara\v0\data');
  final s = Session(dir, clock: DateTime.parse('2026-07-10T09:00:00'), cloud: ClaudeClient(apiKeyOverride: key));
  await s.init(retrieval: false);
  for (final u in setup) { await s.handle(u); }
  final r = await s.handle(probe);
  final ints = s.store.values.where((x)=>x['typeId']=='interaction').toList();
  final contacts = s.store.values.where((x)=>x['typeId']=='contact').map((x)=>x['displayName']).toList();
  final rels = s.store.values.where((x)=>x['typeId']=='contact_relationship').length;
  final facts = s.store.values.where((x)=>x['typeId']=='contact_fact').length;
  final tasks = s.store.values.where((x)=>x['typeId']=='task').length;
  final moods = s.store.values.where((x)=>x['typeId']=='mood').length;
  print('■ $label');
  print('   "$probe"');
  print('   -> $r');
  print('   contacts=$contacts interactions=${ints.length}${ints.isNotEmpty ? ' '+ints.map((i)=>(i['planned']==true?'PLAN':'past')+'@'+i['at'].toString()).toList().toString() : ''}'
        '${rels>0?' rels=$rels':''}${facts>0?' facts=$facts':''}${tasks>0?' tasks=$tasks':''}${moods>0?' moods=$moods':''}');
  print('');
}

void main() async {
  final key = loadConfig().apiKey;
  if (key == null) { print('NO KEY'); return; }
  await run('multi-person PAST', [], 'I had lunch with Sarah Chen and Mike Torres yesterday', key);
  await run('multi-person FUTURE', [], "I'm going to dinner with Katherine and Corey tonight at Ramie", key);
  await run('single PAST', [], 'talked to Sarah about the trip', key);
  await run('single FUTURE', [], 'seeing Dad on friday', key);
  await run('relationship + fact', [], 'Katherine and Corey have three daughters, Rina, Gabriela and Bella', key);
  await run('entity reuse', ['talked to Katherine Zinger'], "having dinner with Katherine tomorrow", key);
  await run('control: one task', [], 'remind me to buy milk and eggs', key);
  await run('control: mood', [], "i'm exhausted", key);
}
