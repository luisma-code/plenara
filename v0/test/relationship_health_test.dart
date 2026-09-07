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
}
