import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plenara/people.dart';
import 'package:plenara/session.dart';

import 'plenara_theme.dart';
import 'presence_shell.dart';
import 'relationship_contacts.dart';
import 'undo_feedback.dart';

class RelationshipsView extends StatefulWidget {
  final Session session;
  final PhoneContactsSource? contactsSource;
  final RelationshipLauncher? launcher;
  final VoidCallback? onVoice;

  const RelationshipsView({
    super.key,
    required this.session,
    this.contactsSource,
    this.launcher,
    this.onVoice,
  });

  @override
  State<RelationshipsView> createState() => _RelationshipsViewState();
}

class _RelationshipsViewState extends State<RelationshipsView> {
  bool _importing = false;

  PhoneContactsSource get _contacts =>
      widget.contactsSource ?? NativePhoneContactsSource();
  RelationshipLauncher get _launcher =>
      widget.launcher ?? SystemRelationshipLauncher();

  void _showResult(ManualWrite result) {
    if (!mounted) return;
    setState(() {});
    showUndoableResult(
      context,
      message: result.message,
      onUndo: result.undoId == null
          ? null
          : () async {
              final message = await widget.session.undoById(result.undoId!);
              if (mounted) setState(() {});
              return message;
            },
    );
  }

  Future<void> _addPerson() async {
    final name = await _askForText(
      context,
      title: 'Add a person',
      label: 'Name',
      action: 'Add',
    );
    if (name == null || name.trim().isEmpty) return;
    _showResult(
      await widget.session.createRecord('contact', {
        'displayName': name.trim(),
        'relationshipGoal': 'none',
      }, description: 'added ${name.trim()}'),
    );
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final available = await _contacts.fetch();
      if (!mounted) return;
      if (available.isEmpty) {
        _message('No contacts with names were found on this device.');
        return;
      }
      // The native read is finished; do not leave an indeterminate spinner
      // animating behind the user's selection dialog.
      setState(() => _importing = false);
      final chosen = await showDialog<List<PhoneContact>>(
        context: context,
        builder: (context) => _ContactPicker(contacts: available),
      );
      if (chosen == null || chosen.isEmpty) return;
      _showResult(
        await widget.session.importContacts(
          chosen.map((contact) => contact.toRecordFields()).toList(),
        ),
      );
    } on PlatformException catch (error) {
      if (mounted) {
        _message(error.message ?? 'Contacts could not be opened.');
      }
    } catch (error) {
      if (mounted) _message('Contacts could not be opened: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPerson(String contactId) async {
    final result = await Navigator.of(context).push<ManualWrite>(
      MaterialPageRoute(
        builder: (_) => PersonRelationshipView(
          session: widget.session,
          contactId: contactId,
          launcher: _launcher,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _showResult(result);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts =
        widget.session.store.values
            .where((record) => record['typeId'] == 'contact')
            .toList()
          ..sort(
            (a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'),
          );
    final statuses = {
      for (final status in relationshipStatuses(
        widget.session.store,
        widget.session.now,
      ))
        status.contactId: status,
    };
    final suggestions = suggestedContacts(
      widget.session.store,
      widget.session.now,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationships'),
        actions: [
          IconButton.filledTonal(
            key: const Key('relationships-voice'),
            tooltip: 'Talk to Plena',
            onPressed: widget.onVoice,
            icon: const Icon(Icons.mic_none_rounded),
          ),
          IconButton(
            key: const Key('relationships-import'),
            tooltip: 'Import from Contacts',
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.contact_page_outlined),
          ),
          IconButton(
            key: const Key('relationships-add-person'),
            tooltip: 'Add person',
            onPressed: _addPerson,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add person'),
      ),
      body: Stack(
        children: [
          ListView(
            key: const Key('relationships-view'),
            padding: const EdgeInsets.fromLTRB(16, 12, 72, 100),
            children: [
              Text(
                'RELATIONSHIPS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PlenaraTheme.amber,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Remember the person, keep a rhythm',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 16),
              if (suggestions.isNotEmpty)
                _NextContactsCard(
                  suggestions: suggestions,
                  onOpen: _openPerson,
                ),
              Row(
                children: [
                  Text(
                    'People',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${contacts.length}',
                    style: const TextStyle(color: PlenaraTheme.quietInk),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (contacts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'No people yet. Add someone directly or bring in their phone and email from Contacts.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _import,
                          icon: const Icon(Icons.contact_page_outlined),
                          label: const Text('Import from Contacts'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final contact in contacts)
                  Card(
                    child: ListTile(
                      key: Key('relationship-person-${contact['id']}'),
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text('${contact['displayName']}'),
                      subtitle: Text(_statusLine(statuses['${contact['id']}'])),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openPerson('${contact['id']}'),
                    ),
                  ),
            ],
          ),
          const PlenaEmber(mode: 'Relationship library.'),
        ],
      ),
    );
  }
}

class _NextContactsCard extends StatelessWidget {
  final List<RelationshipStatus> suggestions;
  final Future<void> Function(String contactId) onOpen;

  const _NextContactsCard({required this.suggestions, required this.onOpen});

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF241B17),
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who to contact next',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          const Text(
            'Based on the rhythms you chose—not generic engagement scores.',
            style: TextStyle(color: PlenaraTheme.quietInk),
          ),
          const Divider(height: 22),
          for (final status in suggestions)
            ListTile(
              key: Key('next-contact-${status.contactId}'),
              contentPadding: EdgeInsets.zero,
              title: Text(status.displayName),
              subtitle: Text(_statusLine(status)),
              trailing: TextButton(
                child: const Text('Open'),
                onPressed: () => onOpen(status.contactId),
              ),
            ),
        ],
      ),
    ),
  );
}

class PersonRelationshipView extends StatefulWidget {
  final Session session;
  final String contactId;
  final RelationshipLauncher? launcher;

  const PersonRelationshipView({
    super.key,
    required this.session,
    required this.contactId,
    this.launcher,
  });

  @override
  State<PersonRelationshipView> createState() => _PersonRelationshipViewState();
}

class _PersonRelationshipViewState extends State<PersonRelationshipView> {
  RelationshipLauncher get _launcher =>
      widget.launcher ?? SystemRelationshipLauncher();

  Map<String, dynamic>? get _contact => widget.session.store[widget.contactId];

  void _showResult(ManualWrite result) {
    if (!mounted) return;
    setState(() {});
    showUndoableResult(
      context,
      message: result.message,
      onUndo: result.undoId == null
          ? null
          : () async {
              final message = await widget.session.undoById(result.undoId!);
              if (mounted) setState(() {});
              return message;
            },
    );
  }

  Future<void> _setGoal(RelationshipGoal goal) async {
    _showResult(
      await widget.session.editFields(widget.contactId, {
        'relationshipGoal': goal.name,
        'contactFrequencyDays': null,
      }),
    );
  }

  Future<void> _customGoal() async {
    final status = relationshipStatuses(
      widget.session.store,
      widget.session.now,
    ).firstWhere((s) => s.contactId == widget.contactId);
    final raw = await _askForText(
      context,
      title: 'Custom contact rhythm',
      label: 'Days between contacts',
      initial: '${status.targetDays ?? 30}',
      action: 'Set rhythm',
      number: true,
    );
    final days = int.tryParse(raw ?? '');
    if (days == null || days < 1) return;
    _showResult(
      await widget.session.editFields(widget.contactId, {
        'relationshipGoal': 'connected',
        'contactFrequencyDays': days,
      }),
    );
  }

  Future<void> _editContactField(String field, String label) async {
    final current = '${_contact?[field] ?? ''}';
    final value = await _askForText(
      context,
      title: 'Edit $label',
      label: label,
      initial: current,
      action: 'Save',
      multiline: field == 'notes',
    );
    if (value == null) return;
    _showResult(await widget.session.editField(widget.contactId, field, value));
  }

  Future<void> _addFact() async {
    final value = await _askForText(
      context,
      title: 'Add a fact',
      label: 'What should Plenara remember?',
      action: 'Remember',
      multiline: true,
    );
    if (value == null || value.trim().isEmpty) return;
    _showResult(
      await widget.session.createRecord(
        'contact_fact',
        {'subject': widget.contactId, 'fact': value.trim()},
        description: 'remembered a fact about ${_contact?['displayName']}',
      ),
    );
  }

  Future<void> _editFact(Map<String, dynamic> fact) async {
    final value = await _askForText(
      context,
      title: 'Edit fact',
      label: 'Fact',
      initial: '${fact['fact'] ?? ''}',
      action: 'Save',
      multiline: true,
    );
    if (value == null) return;
    _showResult(await widget.session.editField('${fact['id']}', 'fact', value));
  }

  Future<void> _logInteraction() async {
    final draft = await showModalBottomSheet<_InteractionDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InteractionEditor(now: widget.session.now),
    );
    if (draft == null) return;
    _showResult(
      await widget.session.createRecord(
        'interaction',
        {
          'subject': widget.contactId,
          'medium': draft.medium,
          'at': _isoDate(draft.at),
          if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
        },
        description:
            'logged ${_mediumLabel(draft.medium)} with ${_contact?['displayName']}',
      ),
    );
  }

  Future<void> _addFollowUp() async {
    final name = '${_contact?['displayName'] ?? 'them'}';
    final today = widget.session.now.toIso8601String().split('T').first;
    _showResult(
      await widget.session.createRecord('task', {
        'description': 'Reach out to $name',
        'createdAt': widget.session.now.toIso8601String(),
        'dueAt': today,
        'status': 'today',
        'contactRefs': [widget.contactId],
      }, description: 'added a follow-up with $name to today'),
    );
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    _showResult(await widget.session.deleteRecord('${record['id']}'));
  }

  Future<void> _launch(Future<bool> Function() action, String failure) async {
    try {
      if (!await action() && mounted) _message(failure);
    } catch (_) {
      if (mounted) _message(failure);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deletePerson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${_contact?['displayName']}?'),
        content: const Text(
          'This removes the person, their facts, dates, relationship links, and interaction history. The action can be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove person'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.session.deleteRecord(widget.contactId);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    if (contact == null) {
      return const Scaffold(body: Center(child: Text('This person is gone.')));
    }
    final status = relationshipStatuses(
      widget.session.store,
      widget.session.now,
    ).firstWhere((s) => s.contactId == widget.contactId);
    final facts = widget.session.store.values
        .where(
          (r) =>
              r['typeId'] == 'contact_fact' &&
              '${r['subject']}' == widget.contactId,
        )
        .toList();
    final interactions =
        widget.session.store.values
            .where(
              (r) =>
                  r['typeId'] == 'interaction' &&
                  '${r['subject']}' == widget.contactId &&
                  r['planned'] != true,
            )
            .toList()
          ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    final phone = '${contact['primaryPhone'] ?? ''}'.trim();
    final email = '${contact['primaryEmail'] ?? ''}'.trim();
    final facetime = phone.isNotEmpty ? phone : email;
    return Scaffold(
      appBar: AppBar(
        title: Text('${contact['displayName']}'),
        actions: [
          IconButton(
            key: const Key('person-delete'),
            tooltip: 'Remove person',
            onPressed: _deletePerson,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            key: const Key('person-relationship-view'),
            padding: const EdgeInsets.fromLTRB(16, 10, 72, 80),
            children: [
              Text(
                _healthTitle(status),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 3),
              Text(
                _statusLine(status),
                style: const TextStyle(color: PlenaraTheme.quietInk),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('log-interaction'),
                    onPressed: _logInteraction,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Log interaction'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('relationship-add-follow-up'),
                    onPressed: _addFollowUp,
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Add follow-up'),
                  ),
                  OutlinedButton.icon(
                    onPressed: phone.isEmpty
                        ? null
                        : () => _launch(
                            () => _launcher.phone(phone),
                            'A phone call could not be opened.',
                          ),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call'),
                  ),
                  OutlinedButton.icon(
                    onPressed: facetime.isEmpty
                        ? null
                        : () => _launch(
                            () => _launcher.facetime(facetime),
                            'FaceTime could not be opened.',
                          ),
                    icon: const Icon(Icons.video_call_outlined),
                    label: const Text('FaceTime'),
                  ),
                  OutlinedButton.icon(
                    onPressed: email.isEmpty
                        ? null
                        : () => _launch(
                            () => _launcher.email(email),
                            'Email could not be opened.',
                          ),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Email'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Relationship rhythm',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How close do you want to keep this relationship?',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _goalChip(
                          'Not tracking',
                          RelationshipGoal.none,
                          status.goal,
                        ),
                        _goalChip(
                          'Close · weekly',
                          RelationshipGoal.close,
                          status.goal,
                        ),
                        _goalChip(
                          'Connected · 3 weeks',
                          RelationshipGoal.connected,
                          status.goal,
                        ),
                        _goalChip(
                          'Light touch · 2 months',
                          RelationshipGoal.light,
                          status.goal,
                        ),
                        ActionChip(
                          key: const Key('relationship-custom-goal'),
                          label: Text(
                            contact['contactFrequencyDays'] == null
                                ? 'Custom rhythm'
                                : 'Custom · ${status.targetDays} days',
                          ),
                          onPressed: _customGoal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Contact details',
                child: Column(
                  children: [
                    _editableRow(
                      'Name',
                      '${contact['displayName']}',
                      'displayName',
                    ),
                    _editableRow('Phone', phone, 'primaryPhone'),
                    _editableRow('Email', email, 'primaryEmail'),
                    _editableRow('Notes', '${contact['notes'] ?? ''}', 'notes'),
                  ],
                ),
              ),
              _Section(
                title: 'Facts',
                action: TextButton.icon(
                  key: const Key('fact-add'),
                  onPressed: _addFact,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add fact'),
                ),
                child: facts.isEmpty
                    ? const Text(
                        'Nothing noted yet.',
                        style: TextStyle(color: PlenaraTheme.quietInk),
                      )
                    : Column(
                        children: [
                          for (final fact in facts)
                            ListTile(
                              key: Key('fact-${fact['id']}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text('${fact['fact']}'),
                              onTap: () => _editFact(fact),
                              trailing: IconButton(
                                tooltip: 'Delete fact',
                                onPressed: () => _deleteRecord(fact),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              _Section(
                title: 'Interaction history',
                action: TextButton.icon(
                  onPressed: _logInteraction,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log'),
                ),
                child: interactions.isEmpty
                    ? const Text(
                        'No interactions logged yet.',
                        style: TextStyle(color: PlenaraTheme.quietInk),
                      )
                    : Column(
                        children: [
                          for (final interaction in interactions)
                            ListTile(
                              key: Key('interaction-${interaction['id']}'),
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _mediumIcon('${interaction['medium'] ?? ''}'),
                                color: PlenaraTheme.amber,
                              ),
                              title: Text(
                                _mediumLabel(
                                  '${interaction['medium'] ?? interaction['kind'] ?? 'interaction'}',
                                ),
                              ),
                              subtitle: Text(
                                [
                                  _friendlyDate('${interaction['at']}'),
                                  if ('${interaction['note'] ?? ''}'
                                      .trim()
                                      .isNotEmpty)
                                    '${interaction['note']}',
                                ].join(' · '),
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete interaction',
                                onPressed: () => _deleteRecord(interaction),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const PlenaEmber(mode: 'Person relationship detail.'),
        ],
      ),
    );
  }

  Widget _goalChip(
    String label,
    RelationshipGoal value,
    RelationshipGoal selected,
  ) => ChoiceChip(
    key: Key('relationship-goal-${value.name}'),
    label: Text(label),
    selected: value == selected && _contact?['contactFrequencyDays'] == null,
    onSelected: (_) => _setGoal(value),
  );

  Widget _editableRow(String label, String value, String field) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value.trim().isEmpty ? 'Not set' : value),
    trailing: const Icon(Icons.edit_outlined, size: 19),
    onTap: () => _editContactField(field, label),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;

  const _Section({required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?action,
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    ),
  );
}

class _ContactPicker extends StatefulWidget {
  final List<PhoneContact> contacts;
  const _ContactPicker({required this.contacts});

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import people'),
    content: SizedBox(
      width: 420,
      height: 420,
      child: ListView.builder(
        itemCount: widget.contacts.length,
        itemBuilder: (_, index) {
          final contact = widget.contacts[index];
          final selected = _selected.contains(contact.systemContactId);
          return CheckboxListTile(
            value: selected,
            title: Text(contact.displayName),
            subtitle: Text(
              contact.primaryPhone ??
                  contact.primaryEmail ??
                  'No phone or email',
            ),
            onChanged: (value) => setState(() {
              if (value == true) {
                _selected.add(contact.systemContactId);
              } else {
                _selected.remove(contact.systemContactId);
              }
            }),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                widget.contacts
                    .where(
                      (contact) => _selected.contains(contact.systemContactId),
                    )
                    .toList(),
              ),
        child: Text('Import ${_selected.length}'),
      ),
    ],
  );
}

class _InteractionDraft {
  final String medium;
  final DateTime at;
  final String note;
  const _InteractionDraft(this.medium, this.at, this.note);
}

class _InteractionEditor extends StatefulWidget {
  final DateTime now;
  const _InteractionEditor({required this.now});

  @override
  State<_InteractionEditor> createState() => _InteractionEditorState();
}

class _InteractionEditorState extends State<_InteractionEditor> {
  String _medium = 'in_person';
  late DateTime _date = widget.now;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log an interaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final medium in const [
                  'in_person',
                  'facetime',
                  'phone',
                  'text',
                  'email',
                ])
                  ChoiceChip(
                    key: Key('interaction-medium-$medium'),
                    label: Text(_mediumLabel(medium)),
                    avatar: Icon(_mediumIcon(medium), size: 17),
                    selected: _medium == medium,
                    onSelected: (_) => setState(() => _medium = medium),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('When'),
              subtitle: Text(_friendlyDate(_isoDate(_date))),
              onTap: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(widget.now.year - 10),
                  lastDate: widget.now,
                );
                if (chosen != null) setState(() => _date = chosen);
              },
            ),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What did you talk about or do? (optional)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('interaction-save'),
                onPressed: () => Navigator.pop(
                  context,
                  _InteractionDraft(_medium, _date, _note.text),
                ),
                child: const Text('Log interaction'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _askForText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = '',
  bool multiline = false,
  bool number = false,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPrompt(
      title: title,
      label: label,
      action: action,
      initial: initial,
      multiline: multiline,
      number: number,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  final String title;
  final String label;
  final String action;
  final String initial;
  final bool multiline;
  final bool number;

  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    required this.initial,
    required this.multiline,
    required this.number,
  });

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: widget.multiline ? 4 : 1,
      keyboardType: widget.number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: widget.multiline
          ? null
          : (_) => Navigator.pop(context, _controller.text),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

String _statusLine(RelationshipStatus? status) {
  if (status == null || status.health == RelationshipHealth.untracked) {
    return 'No contact rhythm set';
  }
  if (status.lastInteractionAt == null) {
    return 'No interaction logged · goal every ${status.targetDays} days';
  }
  final last = _friendlyDate(_isoDate(status.lastInteractionAt!));
  final medium = _mediumLabel(status.lastMedium ?? 'interaction');
  return '$medium · $last · ${_healthTitle(status)}';
}

String _healthTitle(RelationshipStatus status) => switch (status.health) {
  RelationshipHealth.untracked => 'Choose a relationship rhythm',
  RelationshipHealth.noHistory => 'Ready for a first check-in',
  RelationshipHealth.onTrack => 'On track',
  RelationshipHealth.dueSoon => 'Coming due',
  RelationshipHealth.due => 'Due today',
  RelationshipHealth.overdue => 'Ready to reconnect',
};

String _mediumLabel(String medium) => switch (medium) {
  'in_person' => 'In person',
  'facetime' => 'FaceTime',
  'phone' || 'call' => 'Phone call',
  'text' => 'Text',
  'email' => 'Email',
  _ =>
    medium.isEmpty
        ? 'Interaction'
        : '${medium[0].toUpperCase()}${medium.substring(1)}',
};

IconData _mediumIcon(String medium) => switch (medium) {
  'in_person' => Icons.people_outline,
  'facetime' => Icons.video_call_outlined,
  'phone' || 'call' => Icons.call_outlined,
  'text' => Icons.chat_bubble_outline,
  'email' => Icons.email_outlined,
  _ => Icons.favorite_outline,
};

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _friendlyDate(String raw) {
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
