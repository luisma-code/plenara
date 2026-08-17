import 'package:plenara/value_codec.dart';
import 'package:test/test.dart';

Map<String, dynamic> attr(String name, String type,
        [Map<String, dynamic> extra = const {}]) =>
    {
      'name': name,
      'valueType': type,
      'required': false,
      ...extra,
    };

void main() {
  const codec = ValueCodec();

  test(
      'decimal stays an exact string and rejects approximate/non-decimal input',
      () {
    expect(codec.coerce(attr('price', 'decimal'), '12.3400'), '12.3400');
    expect(
      () => codec.coerce(attr('price', 'decimal'), 'NaN'),
      throwsA(isA<ValueCodecError>()
          .having((e) => e.code, 'code', 'invalid_decimal')),
    );
  });

  test('date is real and an explicit datetime offset canonicalizes to UTC', () {
    expect(codec.coerce(attr('day', 'date'), '2026-02-28'), '2026-02-28');
    expect(() => codec.coerce(attr('day', 'date'), '2026-02-30'),
        throwsA(isA<ValueCodecError>()));
    expect(
      codec.coerce(attr('at', 'datetime'), '2026-08-17T10:00:00-07:00'),
      '2026-08-17T17:00:00.000Z',
    );
  });

  test('enum, duration, tags, JSON, and attachments enforce their shapes', () {
    expect(
        codec.coerce(
            attr('state', 'enum', {
              'enumValues': ['open', 'done']
            }),
            'open'),
        'open');
    expect(
        () => codec.coerce(
            attr('state', 'enum', {
              'enumValues': ['open']
            }),
            'lost'),
        throwsA(isA<ValueCodecError>()));
    expect(codec.coerce(attr('seconds', 'duration'), '90'), 90);
    expect(() => codec.coerce(attr('seconds', 'duration'), '1.5'),
        throwsA(isA<ValueCodecError>()));
    expect(codec.coerce(attr('tags', 'tag'), ['home', 'home', ' work ']),
        ['home', 'work']);
    expect(
        codec.coerce(attr('payload', 'json'), {
          'nested': [1, true]
        }),
        {
          'nested': [1, true]
        });
    expect(() => codec.coerce(attr('payload', 'json'), ['not-an-object']),
        throwsA(isA<ValueCodecError>()));
    expect(codec.coerce(attr('photo', 'attachment'), 'attachments/photo.jpg'),
        'attachments/photo.jpg');
    expect(() => codec.coerce(attr('photo', 'attachment'), '../outside.txt'),
        throwsA(isA<ValueCodecError>()));
  });

  test('defaults and many-valued entity references use the same total boundary',
      () {
    final type = {
      'typeId': 'commitment',
      'attributes': [
        {
          'name': 'status',
          'valueType': 'enum',
          'enumValues': ['inbox', 'done'],
          'required': false,
          'default': 'inbox',
        },
        {
          'name': 'people',
          'valueType': 'entityRef',
          'refType': 'contact',
          'cardinality': 'many',
          'required': false,
        },
      ],
    };
    final records = {
      'c1': {'id': 'c1', 'typeId': 'contact'},
      'c2': {'id': 'c2', 'typeId': 'contact'},
    };
    final result = codec.validateRecord(
      type,
      {
        'id': 'x',
        'typeId': 'commitment',
        'people': ['c1', 'c2']
      },
      records: records,
    );
    expect(result['status'], 'inbox');
    expect(result['people'], ['c1', 'c2']);
    expect(
      () => codec.validateRecord(
        type,
        {
          'id': 'x',
          'typeId': 'commitment',
          'people': ['missing']
        },
        records: records,
      ),
      throwsA(isA<ValueCodecError>()),
    );
  });

  test('entity references validate existence and target type', () {
    final records = {
      'contact-1': {
        'id': 'contact-1',
        'typeId': 'contact',
        'displayName': 'Mia'
      },
    };
    final relation = attr('person', 'entityRef', {'refType': 'contact'});
    expect(codec.coerce(relation, 'contact-1', records: records), 'contact-1');
    expect(() => codec.coerce(relation, 'missing', records: records),
        throwsA(isA<ValueCodecError>()));
    expect(
      () => codec.coerce(
          attr('task', 'entityRef', {'refType': 'task'}), 'contact-1',
          records: records),
      throwsA(isA<ValueCodecError>()
          .having((e) => e.code, 'code', 'wrong_entity_type')),
    );
  });

  test('record validation rejects unknown fields and required nulls', () {
    final type = {
      'typeId': 'task',
      'attributes': [
        {'name': 'description', 'valueType': 'text', 'required': true},
      ],
    };
    expect(
      () => codec
          .validateRecord(type, {'id': 't1', 'typeId': 'task', 'extra': true}),
      throwsA(isA<ValueCodecError>()
          .having((e) => e.code, 'code', 'unknown_field')),
    );
    expect(
      () => codec.validateRecord(
          type, {'id': 't1', 'typeId': 'task', 'description': null}),
      throwsA(isA<ValueCodecError>()
          .having((e) => e.code, 'code', 'required_null')),
    );
  });
}
