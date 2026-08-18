import 'dart:io';

import 'package:plenara/planning_artifact.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.parse('2026-08-17T08:00:00');

  test('morning plan prioritizes scheduled, due, then high-priority truth', () {
    final artifact = buildMorningPlanningArtifact({
      'scheduled': {
        'id': 'scheduled',
        'typeId': 'task',
        'description': 'School dropoff',
        'scheduledStartAt': '2026-08-17T08:30:00',
      },
      'due': {
        'id': 'due',
        'typeId': 'task',
        'description': 'Submit form',
        'dueAt': '2026-08-17',
      },
      'high': {
        'id': 'high',
        'typeId': 'task',
        'description': 'Call Dad',
        'priority': 'high',
      },
    }, now);

    expect(
      artifact.items.map((item) => item.recordId),
      ['scheduled', 'due', 'high'],
    );
    expect(artifact.items.every((item) => item.evidence.isNotEmpty), isTrue);
  });

  test('relationship prep uses only saved facts and latest interaction', () {
    final artifact = buildRelationshipPrepArtifact(
        'Sam',
        {
          'sam': {'id': 'sam', 'typeId': 'contact', 'displayName': 'Sam'},
          'fact': {
            'id': 'fact',
            'typeId': 'contact_fact',
            'subject': 'sam',
            'fact': 'Loves jazz',
          },
          'old': {
            'id': 'old',
            'typeId': 'interaction',
            'subject': 'sam',
            'at': '2026-07-01',
            'note': 'Old thread',
          },
          'new': {
            'id': 'new',
            'typeId': 'interaction',
            'subject': 'sam',
            'at': '2026-08-01',
            'note': 'Concert plans',
          },
        },
        now)!;

    expect(artifact.items.map((item) => item.title),
        containsAll(['Loves jazz', 'Concert plans']));
    expect(artifact.items.map((item) => item.title),
        isNot(contains('Old thread')));
  });

  test('relationship preps supersede per subject, never across people', () {
    final dir = Directory.systemTemp.createTempSync('plenara_artifacts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/artifacts.json';
    final records = {
      'alice': {'id': 'alice', 'typeId': 'contact', 'displayName': 'Alice'},
      'bob': {'id': 'bob', 'typeId': 'contact', 'displayName': 'Bob'},
    };
    final store = PlanningArtifactStore(path: path);
    final aliceOld = buildRelationshipPrepArtifact('Alice', records, now)!;
    store.create(aliceOld);
    final bobPrep = buildRelationshipPrepArtifact(
        'Bob', records, now.add(const Duration(minutes: 1)))!;
    store.create(bobPrep);

    // Bob's prep must not kill Alice's still-open prep.
    expect(
      store.active.map((artifact) => artifact.id),
      containsAll([aliceOld.id, bobPrep.id]),
    );

    final aliceNew = buildRelationshipPrepArtifact(
        'Alice', records, now.add(const Duration(minutes: 2)))!;
    store.create(aliceNew);

    final reopened = PlanningArtifactStore(path: path);
    expect(
      reopened.active.map((artifact) => artifact.id),
      containsAll([aliceNew.id, bobPrep.id]),
    );
    expect(
      reopened.history
          .firstWhere((artifact) => artifact.id == aliceOld.id)
          .state,
      PlanningArtifactState.superseded,
    );
  });

  test('artifact persists until resolved and a new one supersedes its peer',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_artifacts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/artifacts.json';
    final store = PlanningArtifactStore(path: path);
    final first = buildMorningPlanningArtifact({}, now);
    store.create(first);
    final second = buildMorningPlanningArtifact(
      {},
      now.add(const Duration(minutes: 1)),
    );
    store.create(second);

    final reopened = PlanningArtifactStore(path: path);
    expect(reopened.active.single.id, second.id);
    expect(reopened.history.first.state, PlanningArtifactState.superseded);
    reopened.resolve(second.id, PlanningArtifactState.accepted, now);
    expect(PlanningArtifactStore(path: path).active, isEmpty);
  });
}
