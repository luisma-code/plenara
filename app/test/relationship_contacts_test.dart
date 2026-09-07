import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/relationship_contacts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native picker logs and decodes every selection attempt', () async {
    const channel = MethodChannel('com.plenara/contacts-test');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'select');
          calls++;
          return <String, Object?>{
            'authorizationStatus': calls == 1 ? 'limited' : 'denied',
            'cancelled': false,
            'contacts': [
              <String, Object?>{
                'identifier': 'ios-bob',
                'displayName': 'Bob Rivera',
                'phone': calls == 1 ? '+15551212' : '+15559999',
                'email': 'bob@example.com',
              },
            ],
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final logs = <String>[];
    final source = NativePhoneContactsSource(channel: channel, log: logs.add);

    final first = await source.select();
    final second = await source.select();

    expect(calls, 2);
    expect(first.single.primaryPhone, '+15551212');
    expect(second.single.primaryPhone, '+15559999');
    expect(logs, [
      'contacts: picker begin',
      'contacts: picker finished (authorization=limited, selected=1)',
      'contacts: picker begin',
      'contacts: picker finished (authorization=denied, selected=1)',
    ]);
  });

  test(
    'native picker logs cancellation without treating it as no contacts',
    () async {
      const channel = MethodChannel('com.plenara/contacts-cancel-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{
              'authorizationStatus': 'limited',
              'cancelled': true,
              'contacts': const <Object?>[],
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final logs = <String>[];
      final source = NativePhoneContactsSource(channel: channel, log: logs.add);

      expect(await source.select(), isEmpty);
      expect(logs, [
        'contacts: picker begin',
        'contacts: picker cancelled (authorization=limited)',
      ]);
    },
  );
}
