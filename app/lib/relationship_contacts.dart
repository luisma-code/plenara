import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class PhoneContact {
  final String systemContactId;
  final String displayName;
  final String? primaryPhone;
  final String? primaryEmail;

  const PhoneContact({
    required this.systemContactId,
    required this.displayName,
    this.primaryPhone,
    this.primaryEmail,
  });

  Map<String, Object?> toRecordFields() => {
    'systemContactId': systemContactId,
    'displayName': displayName,
    if (primaryPhone != null) 'primaryPhone': primaryPhone,
    if (primaryEmail != null) 'primaryEmail': primaryEmail,
  };
}

abstract interface class PhoneContactsSource {
  Future<List<PhoneContact>> fetch();
}

class NativePhoneContactsSource implements PhoneContactsSource {
  static const _channel = MethodChannel('com.plenara/contacts');

  @override
  Future<List<PhoneContact>> fetch() async {
    final raw = await _channel.invokeListMethod<Object?>('fetch');
    return [
      for (final value in raw ?? const [])
        if (value is Map && '${value['displayName'] ?? ''}'.trim().isNotEmpty)
          PhoneContact(
            systemContactId: '${value['identifier'] ?? ''}',
            displayName: '${value['displayName']}'.trim(),
            primaryPhone: _nonEmpty(value['phone']),
            primaryEmail: _nonEmpty(value['email']),
          ),
    ];
  }

  static String? _nonEmpty(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

abstract interface class RelationshipLauncher {
  Future<bool> phone(String number);
  Future<bool> facetime(String address);
  Future<bool> email(String address);
}

class SystemRelationshipLauncher implements RelationshipLauncher {
  Future<bool> _open(String scheme, String target) => launchUrl(
    Uri(scheme: scheme, path: target),
    mode: LaunchMode.externalApplication,
  );

  @override
  Future<bool> phone(String number) => _open('tel', number);

  @override
  Future<bool> facetime(String address) => _open('facetime', address);

  @override
  Future<bool> email(String address) => _open('mailto', address);
}
