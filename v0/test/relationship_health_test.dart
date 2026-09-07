import 'package:plenara/people.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.parse('2026-09-06T12:00:00');

  test('relationship health follows each chosen contact rhythm', () {
    final statuses = relationshipStatuses({
      'close': {
        'id': 'close',
        'typeId': 'contact',
        'displayName': 'Mia',
        'relationshipGoal': 'close',
      },
      'light': {
        'id': 'light',
        'typeId': 'contact',
        'displayName': 'Sam',
        'relationshipGoal': 'light',
      },
      'none': {
        'id': 'none',
        'typeId': 'contact',
        'displayName': 'Jo',
        'relationshipGoal': 'none',
      },
      'mia-call': {
        'id': 'mia-call',
        'typeId': 'interaction',
        'subject': 'close',
        'medium': 'facetime',
        'at': '2026-08-28',
      },
      'sam-text': {
        'id': 'sam-text',
        'typeId': 'interaction',
        'subject': 'light',
        'medium': 'text',
        'at': '2026-08-28',
      },
    }, now);

    final mia = statuses.singleWhere((status) => status.contactId == 'close');
    final sam = statuses.singleWhere((status) => status.contactId == 'light');
    final jo = statuses.singleWhere((status) => status.contactId == 'none');
    expect(mia.targetDays, 7);
    expect(mia.health, RelationshipHealth.overdue);
    expect(mia.lastMedium, 'facetime');
    expect(sam.targetDays, 60);
    expect(sam.health, RelationshipHealth.onTrack);
    expect(jo.health, RelationshipHealth.untracked);
    expect(
        suggestedContacts({
          for (final entry in <String, Map<String, dynamic>>{
            'close': {
              'id': 'close',
              'typeId': 'contact',
              'displayName': 'Mia',
              'relationshipGoal': 'close',
            },
            'mia-call': {
              'id': 'mia-call',
              'typeId': 'interaction',
              'subject': 'close',
              'medium': 'facetime',
              'at': '2026-08-28',
            },
          }.entries)
            entry.key: entry.value,
        }, now)
            .single
            .contactId,
        'close');
  });

  test('planned interactions never claim relationship follow-through', () {
    final status = relationshipStatuses({
      'mia': {
        'id': 'mia',
        'typeId': 'contact',
        'displayName': 'Mia',
        'relationshipGoal': 'connected',
      },
      'plan': {
        'id': 'plan',
        'typeId': 'interaction',
        'subject': 'mia',
        'medium': 'in_person',
        'at': '2026-09-07',
        'planned': true,
      },
    }, now)
        .single;
    expect(status.health, RelationshipHealth.noHistory);
    expect(status.lastInteractionAt, isNull);
  });

  test('an exact frequency overrides the closeness preset', () {
    expect(
      relationshipTargetDays({
        'relationshipGoal': 'close',
        'contactFrequencyDays': 10,
      }),
      10,
    );
  });

  test('circle defaults drive independent touch and meaningful clocks', () {
    final status = relationshipStatuses({
      'mia': {
        'id': 'mia',
        'typeId': 'contact',
        'displayName': 'Mia',
        ...relationshipPresetFields(RelationshipPreset.closeRemoteFriend),
      },
      'call': {
        'id': 'call',
        'typeId': 'interaction',
        'subject': 'mia',
        'medium': 'phone',
        'connectionDepth': 'meaningful',
        'at': '2026-08-01',
      },
      'text': {
        'id': 'text',
        'typeId': 'interaction',
        'subject': 'mia',
        'medium': 'text',
        'connectionDepth': 'quick',
        'at': '2026-09-01',
      },
    }, now)
        .single;

    expect(status.circle, RelationshipCircle.close);
    expect(status.proximity, 'remote');
    expect(status.touchTargetDays, 14);
    expect(status.meaningfulTargetDays, 30);
    expect(status.lastTouchAt, DateTime.parse('2026-09-01'));
    expect(status.lastMeaningfulAt, DateTime.parse('2026-08-01'));
    expect(status.need, RelationshipNeed.meaningful);
  });

  test('depth is explicit, while legacy interactions infer it from medium', () {
    expect(
      connectionDepthOf({'medium': 'text', 'connectionDepth': 'meaningful'}),
      ConnectionDepth.meaningful,
    );
    expect(connectionDepthOf({'medium': 'text'}), ConnectionDepth.quick);
    expect(
      connectionDepthOf({'medium': 'facetime'}),
      ConnectionDepth.meaningful,
    );
  });

  test('paused and context-only people keep history without suggestions', () {
    final records = <String, Map<String, dynamic>>{
      'neighbor': {
        'id': 'neighbor',
        'typeId': 'contact',
        'displayName': 'Jo',
        ...relationshipPresetFields(RelationshipPreset.neighbor),
      },
      'paused': {
        'id': 'paused',
        'typeId': 'contact',
        'displayName': 'Sam',
        ...relationshipPresetFields(RelationshipPreset.closeFamily),
        'relationshipStatus': 'paused',
      },
    };
    expect(suggestedContacts(records, now), isEmpty);
    expect(
      relationshipStatuses(records, now)
          .every((status) => status.health == RelationshipHealth.untracked),
      isTrue,
    );
  });
}
