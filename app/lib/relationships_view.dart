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
  final Widget? menuAction;

  const RelationshipsView({
    super.key,
    required this.session,
    this.contactsSource,
    this.launcher,
    this.onVoice,
    this.menuAction,
  });

  @override
  State<RelationshipsView> createState() => _RelationshipsViewState();
}

class _RelationshipsViewState extends State<RelationshipsView> {
  bool _importing = false;
  bool _showAllPeople = false;
  bool _showAllAttention = false;
  bool _organizing = false;
  String _query = '';
  RelationshipCircle? _selectedCircle;
  String? _selectedProximity;
  final Set<String> _selectedPeople = {};
  final TextEditingController _searchController = TextEditingController();

  PhoneContactsSource get _contacts =>
      widget.contactsSource ?? NativePhoneContactsSource();
  RelationshipLauncher get _launcher =>
      widget.launcher ?? SystemRelationshipLauncher();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        ...relationshipPresetFields(RelationshipPreset.contextOnly),
      }, description: 'added ${name.trim()}'),
    );
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final chosen = await _contacts.select();
      if (!mounted) return;
      if (chosen.isEmpty) return;
      final preset = await showModalBottomSheet<RelationshipPreset>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ImportOrganizer(count: chosen.length),
      );
      if (!mounted || preset == null) return;
      _showResult(
        await widget.session.importContacts(
          chosen
              .map(
                (contact) => <String, Object?>{
                  ...contact.toRecordFields(),
                  ...relationshipPresetFields(preset),
                },
              )
              .toList(),
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

  Future<void> _movePerson(String contactId, RelationshipCircle circle) async {
    _showResult(await widget.session.setRelationshipCircle(contactId, circle));
  }

  Future<void> _setPersonProximity(String contactId, String proximity) async {
    _showResult(
      await widget.session.setRelationshipProximity(contactId, proximity),
    );
  }

  Future<void> _organizeSelected() async {
    if (_selectedPeople.isEmpty) return;
    final choice = await showModalBottomSheet<_OrganizationChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupOrganizer(count: _selectedPeople.length),
    );
    if (!mounted || choice == null) return;
    final ids = _selectedPeople.toList(growable: false);
    final result = choice.circle != null
        ? await widget.session.setRelationshipCircles(ids, choice.circle!)
        : await widget.session.setRelationshipProximities(
            ids,
            choice.proximity!,
          );
    if (result.ok && mounted) {
      setState(() {
        _selectedPeople.clear();
        _organizing = false;
      });
    }
    _showResult(result);
  }

  void _toggleOrganizing() {
    setState(() {
      _organizing = !_organizing;
      _selectedPeople.clear();
      if (_organizing && _selectedCircle == null && !_showAllPeople) {
        _showAllPeople = true;
      }
    });
  }

  void _selectStatus(RelationshipStatus status) {
    if (_organizing) {
      setState(() {
        if (!_selectedPeople.add(status.contactId)) {
          _selectedPeople.remove(status.contactId);
        }
      });
      return;
    }
    _openPerson(status.contactId);
  }

  void _showFocus() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedCircle = null;
      _selectedProximity = null;
      _showAllPeople = false;
      _showAllAttention = false;
    });
  }

  void _showCircle(RelationshipCircle circle) {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedCircle = circle;
      _showAllPeople = false;
    });
  }

  void _showProximity(String proximity) {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedProximity = proximity;
      _showAllPeople = true;
    });
  }

  void _showEverywhere() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedProximity = null;
      _showAllPeople = true;
    });
  }

  void _showEveryone() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedCircle = null;
      _showAllPeople = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statuses = relationshipStatuses(
      widget.session.store,
      widget.session.now,
    );
    final attention = statuses
        .where((status) => status.needsContact)
        .toList(growable: false);
    final normalizedQuery = _query.trim().toLowerCase();
    final searchResults = normalizedQuery.isEmpty
        ? const <RelationshipStatus>[]
        : statuses
              .where(
                (status) =>
                    status.displayName.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
    final isFocus =
        normalizedQuery.isEmpty &&
        _selectedCircle == null &&
        _selectedProximity == null &&
        !_showAllPeople;
    final facetedStatuses = statuses
        .where(
          (status) =>
              (_selectedCircle == null || status.circle == _selectedCircle) &&
              (_selectedProximity == null ||
                  status.proximity == _selectedProximity),
        )
        .toList(growable: false);
    final prioritizedStatuses = normalizedQuery.isNotEmpty
        ? searchResults
        : !isFocus
        ? facetedStatuses
        : (_showAllAttention ? attention : attention.take(8).toList());
    final selectedStatuses = List<RelationshipStatus>.of(prioritizedStatuses)
      ..sort(_compareRelationshipNames);
    final title = normalizedQuery.isNotEmpty
        ? 'Search results'
        : _selectedCircle != null && _selectedProximity != null
        ? '${relationshipCircleLabel(_selectedCircle!)} · ${relationshipProximityLabel(_selectedProximity!)}'
        : _selectedProximity != null
        ? '${relationshipProximityLabel(_selectedProximity!)} relationships'
        : _selectedCircle != null
        ? relationshipCircleLabel(_selectedCircle!)
        : _showAllPeople
        ? 'All people'
        : 'Needs attention';
    final subtitle = normalizedQuery.isNotEmpty
        ? '${searchResults.length} ${searchResults.length == 1 ? 'person' : 'people'} found across every circle. Alphabetized by name.'
        : _selectedProximity != null
        ? '${relationshipProximityGuidance(_selectedProximity!)}. Alphabetized by name.'
        : _selectedCircle != null
        ? _circleDescription(_selectedCircle!)
        : _showAllPeople
        ? 'Everyone, alphabetized by name.'
        : 'Selected by relationship urgency, alphabetized by name.';
    final circleCounts = <RelationshipCircle, int>{
      for (final circle in RelationshipCircle.values)
        circle: statuses
            .where(
              (status) =>
                  status.circle == circle &&
                  (_selectedProximity == null ||
                      status.proximity == _selectedProximity),
            )
            .length,
    };
    final circleAttentionCounts = <RelationshipCircle, int>{
      for (final circle in RelationshipCircle.values)
        circle: attention
            .where(
              (status) =>
                  status.circle == circle &&
                  (_selectedProximity == null ||
                      status.proximity == _selectedProximity),
            )
            .length,
    };
    final proximityCounts = <String, int>{
      for (final proximity in relationshipProximities)
        proximity: statuses
            .where(
              (status) =>
                  status.proximity == proximity &&
                  (_selectedCircle == null || status.circle == _selectedCircle),
            )
            .length,
    };
    final proximityAttentionCounts = <String, int>{
      for (final proximity in relationshipProximities)
        proximity: attention
            .where(
              (status) =>
                  status.proximity == proximity &&
                  (_selectedCircle == null || status.circle == _selectedCircle),
            )
            .length,
    };
    final totalPeople = statuses.length;
    final circleScopeCount = _selectedProximity == null
        ? totalPeople
        : statuses
              .where((status) => status.proximity == _selectedProximity)
              .length;
    final proximityScopeCount = _selectedCircle == null
        ? totalPeople
        : statuses.where((status) => status.circle == _selectedCircle).length;
    final peopleLabel =
        '$totalPeople ${totalPeople == 1 ? 'person' : 'people'}';
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
          ?widget.menuAction,
        ],
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
                'Keep the people who matter in view',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$peopleLabel · ${attention.length} need attention',
                style: const TextStyle(color: PlenaraTheme.quietInk),
              ),
              const SizedBox(height: 14),
              SearchBar(
                key: const Key('relationships-search'),
                controller: _searchController,
                hintText: 'Find a person in any circle',
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Relationship circle',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('relationships-organize'),
                    onPressed: statuses.isEmpty ? null : _toggleOrganizing,
                    icon: Icon(
                      _organizing
                          ? Icons.close_rounded
                          : Icons.groups_2_outlined,
                      size: 18,
                    ),
                    label: Text(_organizing ? 'Done' : 'Organize'),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 42,
                child: SingleChildScrollView(
                  key: const Key('relationship-circle-filters'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        key: const Key('relationships-filter-focus'),
                        selected: isFocus,
                        avatar: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                        ),
                        label: Text('Focus · ${attention.length}'),
                        onSelected: (_) => _showFocus(),
                      ),
                      const SizedBox(width: 7),
                      for (final circle in RelationshipCircle.values) ...[
                        ChoiceChip(
                          key: Key('relationships-filter-${circle.name}'),
                          selected:
                              normalizedQuery.isEmpty &&
                              _selectedCircle == circle,
                          label: Text(
                            '${relationshipCircleLabel(circle)} · ${circleCounts[circle]}',
                          ),
                          avatar: circleAttentionCounts[circle] == 0
                              ? null
                              : CircleAvatar(
                                  child: Text(
                                    '${circleAttentionCounts[circle]}',
                                  ),
                                ),
                          onSelected: (_) => _showCircle(circle),
                        ),
                        const SizedBox(width: 7),
                      ],
                      ChoiceChip(
                        key: const Key('relationships-filter-all'),
                        selected:
                            normalizedQuery.isEmpty &&
                            _showAllPeople &&
                            _selectedCircle == null,
                        label: Text('All circles · $circleScopeCount'),
                        onSelected: (_) => _showEveryone(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Where they are',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 42,
                child: SingleChildScrollView(
                  key: const Key('relationship-proximity-filters'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        key: const Key('relationships-proximity-any'),
                        selected:
                            normalizedQuery.isEmpty &&
                            _selectedProximity == null &&
                            !isFocus,
                        label: Text('Everywhere · $proximityScopeCount'),
                        onSelected: (_) => _showEverywhere(),
                      ),
                      const SizedBox(width: 7),
                      for (final proximity in relationshipProximities) ...[
                        ChoiceChip(
                          key: Key('relationships-proximity-$proximity'),
                          selected:
                              normalizedQuery.isEmpty &&
                              _selectedProximity == proximity,
                          avatar: proximityAttentionCounts[proximity] == 0
                              ? null
                              : CircleAvatar(
                                  child: Text(
                                    '${proximityAttentionCounts[proximity]}',
                                  ),
                                ),
                          label: Text(
                            '${relationshipProximityLabel(proximity)} · ${proximityCounts[proximity]}',
                          ),
                          onSelected: (_) => _showProximity(proximity),
                        ),
                        const SizedBox(width: 7),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_organizing)
                Card(
                  color: const Color(0xFF241B17),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selectedPeople.length} selected',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: _selectedPeople.isEmpty
                              ? null
                              : () => setState(_selectedPeople.clear),
                          child: const Text('Clear'),
                        ),
                        FilledButton.icon(
                          key: const Key('relationships-move-selected'),
                          onPressed: _selectedPeople.isEmpty
                              ? null
                              : _organizeSelected,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Organize'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (statuses.isEmpty)
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
              else ...[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: PlenaraTheme.quietInk),
                ),
                const SizedBox(height: 8),
                if (selectedStatuses.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        normalizedQuery.isNotEmpty
                            ? 'No one matches “${_query.trim()}”.'
                            : isFocus
                            ? 'You’re caught up. No relationship goal needs attention right now.'
                            : _selectedProximity != null
                            ? 'No one is marked ${relationshipProximityLabel(_selectedProximity!).toLowerCase()} in this circle.'
                            : 'No one is in this circle yet.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PlenaraTheme.quietInk),
                      ),
                    ),
                  )
                else
                  for (final status in selectedStatuses)
                    _RelationshipRow(
                      status: status,
                      selected: _selectedPeople.contains(status.contactId),
                      organizing: _organizing,
                      onTap: () => _selectStatus(status),
                      onMove: (circle) => _movePerson(status.contactId, circle),
                      onProximity: (proximity) =>
                          _setPersonProximity(status.contactId, proximity),
                    ),
                if (isFocus &&
                    !_showAllAttention &&
                    attention.length > selectedStatuses.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('relationships-show-all-attention'),
                      onPressed: () => setState(() => _showAllAttention = true),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        'Show all ${attention.length} needing attention',
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const PlenaEmber(mode: 'Relationship library.'),
        ],
      ),
    );
  }
}

int _compareRelationshipNames(RelationshipStatus a, RelationshipStatus b) {
  final folded = a.displayName.trim().toLowerCase().compareTo(
    b.displayName.trim().toLowerCase(),
  );
  if (folded != 0) return folded;
  final exact = a.displayName.trim().compareTo(b.displayName.trim());
  return exact != 0 ? exact : a.contactId.compareTo(b.contactId);
}

class _RelationshipRow extends StatelessWidget {
  final RelationshipStatus status;
  final bool selected;
  final bool organizing;
  final VoidCallback onTap;
  final ValueChanged<RelationshipCircle> onMove;
  final ValueChanged<String> onProximity;

  const _RelationshipRow({
    required this.status,
    required this.selected,
    required this.organizing,
    required this.onTap,
    required this.onMove,
    required this.onProximity,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    child: ListTile(
      key: Key('relationship-person-${status.contactId}'),
      isThreeLine: true,
      selected: selected,
      leading: organizing
          ? Checkbox(
              key: Key('relationship-select-${status.contactId}'),
              value: selected,
              onChanged: (_) => onTap(),
            )
          : CircleAvatar(
              backgroundColor: status.needsContact
                  ? PlenaraTheme.amber.withValues(alpha: 0.16)
                  : null,
              child: Text(
                status.displayName.trim().isEmpty
                    ? '?'
                    : status.displayName.trim().characters.first.toUpperCase(),
              ),
            ),
      title: Text(status.displayName),
      subtitle: Text(
        '${relationshipCircleLabel(status.circle)} · ${relationshipProximityLabel(status.proximity)}\n${status.needsContact ? _suggestionLine(status) : _statusLine(status)}',
      ),
      trailing: organizing
          ? null
          : PopupMenuButton<String>(
              key: Key('relationship-move-${status.contactId}'),
              tooltip: 'Organize ${status.displayName}',
              onSelected: (choice) {
                final parts = choice.split(':');
                if (parts.first == 'circle') {
                  onMove(
                    RelationshipCircle.values.firstWhere(
                      (circle) => circle.name == parts.last,
                    ),
                  );
                } else {
                  onProximity(parts.last);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  enabled: false,
                  height: 36,
                  child: Text('RELATIONSHIP CIRCLE'),
                ),
                for (final circle in RelationshipCircle.values)
                  PopupMenuItem<String>(
                    key: Key(
                      'relationship-move-${status.contactId}-${circle.name}',
                    ),
                    value: 'circle:${circle.name}',
                    enabled: circle != status.circle,
                    height: 58,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: circle == status.circle
                              ? const Icon(Icons.check_rounded, size: 18)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(relationshipCircleLabel(circle)),
                              Text(
                                _circleCadence(circle),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  enabled: false,
                  height: 36,
                  child: Text('WHERE THEY ARE'),
                ),
                for (final proximity in relationshipProximities)
                  PopupMenuItem<String>(
                    key: Key(
                      'relationship-proximity-${status.contactId}-$proximity',
                    ),
                    value: 'proximity:$proximity',
                    enabled: proximity != status.proximity,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: proximity == status.proximity
                              ? const Icon(Icons.check_rounded, size: 18)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(relationshipProximityLabel(proximity)),
                              Text(
                                relationshipProximityGuidance(proximity),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Organize'),
                    SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
      onTap: onTap,
    ),
  );
}

class _OrganizationChoice {
  final RelationshipCircle? circle;
  final String? proximity;

  const _OrganizationChoice.circle(RelationshipCircle value)
    : circle = value,
      proximity = null;

  const _OrganizationChoice.proximity(String value)
    : circle = null,
      proximity = value;
}

class _GroupOrganizer extends StatelessWidget {
  final int count;

  const _GroupOrganizer({required this.count});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organize $count ${count == 1 ? 'person' : 'people'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Set how close you want to stay or where people are. These are independent.',
              style: TextStyle(color: PlenaraTheme.quietInk),
            ),
            const SizedBox(height: 14),
            Text(
              'Relationship circle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Moving circles applies that circle’s contact goals.',
              style: TextStyle(color: PlenaraTheme.quietInk),
            ),
            const SizedBox(height: 6),
            for (final circle in RelationshipCircle.values)
              ListTile(
                key: Key('relationships-bulk-circle-${circle.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(relationshipCircleLabel(circle)),
                subtitle: Text(_circleCadence(circle)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.pop(context, _OrganizationChoice.circle(circle)),
              ),
            const Divider(height: 28),
            Text(
              'Where they are',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Location changes suggestions, not contact frequency.',
              style: TextStyle(color: PlenaraTheme.quietInk),
            ),
            const SizedBox(height: 6),
            for (final proximity in relationshipProximities)
              ListTile(
                key: Key('relationships-bulk-proximity-$proximity'),
                contentPadding: EdgeInsets.zero,
                title: Text(relationshipProximityLabel(proximity)),
                subtitle: Text(relationshipProximityGuidance(proximity)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(
                  context,
                  _OrganizationChoice.proximity(proximity),
                ),
              ),
          ],
        ),
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

  Future<void> _setPreset(RelationshipPreset preset) async {
    _showResult(
      await widget.session.setRelationshipPreset(widget.contactId, preset),
    );
  }

  Future<void> _setCircle(RelationshipCircle circle) async {
    _showResult(
      await widget.session.setRelationshipCircle(widget.contactId, circle),
    );
  }

  Future<void> _customGoal({required bool meaningful}) async {
    final status = relationshipStatuses(
      widget.session.store,
      widget.session.now,
    ).firstWhere((s) => s.contactId == widget.contactId);
    final raw = await _askForText(
      context,
      title: meaningful ? 'Meaningful connection goal' : 'Contact goal',
      label: meaningful
          ? 'Days between meaningful connections'
          : 'Days between any contact',
      initial:
          '${meaningful ? status.meaningfulTargetDays ?? 30 : status.touchTargetDays ?? 14}',
      action: 'Set goal',
      number: true,
    );
    final days = int.tryParse(raw ?? '');
    if (days == null || days < 1) return;
    _showResult(
      await widget.session.editFields(widget.contactId, {
        meaningful ? 'trackMeaningful' : 'trackTouch': true,
        meaningful ? 'meaningfulFrequencyDays' : 'touchFrequencyDays': days,
      }),
    );
  }

  Future<void> _toggleGoal({required bool meaningful, required bool on}) async {
    final status = relationshipStatuses(
      widget.session.store,
      widget.session.now,
    ).firstWhere((value) => value.contactId == widget.contactId);
    final target = meaningful
        ? status.meaningfulTargetDays
        : status.touchTargetDays;
    _showResult(
      await widget.session.editFields(widget.contactId, {
        meaningful ? 'trackMeaningful' : 'trackTouch': on,
        if (on && target == null)
          meaningful ? 'meaningfulFrequencyDays' : 'touchFrequencyDays': 30,
      }),
    );
  }

  Future<void> _setProximity(String value) async {
    _showResult(
      await widget.session.editField(widget.contactId, 'proximity', value),
    );
  }

  Future<void> _setEngagement(RelationshipEngagement value) async {
    _showResult(
      await widget.session.editField(
        widget.contactId,
        'relationshipStatus',
        value.name,
      ),
    );
  }

  Future<void> _editRoles() async {
    final roles =
        (_contact?['relationshipRoles'] as List?)
            ?.map((value) => '$value')
            .join(', ') ??
        '';
    final value = await _askForText(
      context,
      title: 'Relationship roles',
      label: 'Family, Friend, Neighbor, Work…',
      initial: roles,
      action: 'Save roles',
    );
    if (value == null) return;
    final parsed = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toSet()
        .toList();
    _showResult(
      await widget.session.editField(
        widget.contactId,
        'relationshipRoles',
        parsed,
      ),
    );
  }

  Future<void> _chooseIntroducedBy() async {
    final people =
        widget.session.store.values
            .where(
              (record) =>
                  record['typeId'] == 'contact' &&
                  '${record['id']}' != widget.contactId,
            )
            .toList()
          ..sort(
            (a, b) => '${a['displayName']}'.compareTo('${b['displayName']}'),
          );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Introduced by'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('No one / clear'),
          ),
          for (final person in people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '${person['id']}'),
              child: Text('${person['displayName']}'),
            ),
        ],
      ),
    );
    if (value == null) return;
    _showResult(
      await widget.session.editFields(widget.contactId, {
        'introducedBy': value.isEmpty ? null : value,
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
          'connectionDepth': draft.depth.name,
          'at': _isoDate(draft.at),
          if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
        },
        description:
            'logged ${_mediumLabel(draft.medium)} with ${_contact?['displayName']}',
      ),
    );
  }

  Future<void> _editInteraction(Map<String, dynamic> interaction) async {
    final draft = await showModalBottomSheet<_InteractionDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _InteractionEditor(now: widget.session.now, initial: interaction),
    );
    if (draft == null) return;
    _showResult(
      await widget.session.editFields('${interaction['id']}', {
        'medium': draft.medium,
        'connectionDepth': draft.depth.name,
        'at': _isoDate(draft.at),
        'note': draft.note.trim().isEmpty ? null : draft.note.trim(),
      }),
    );
  }

  Future<void> _addFollowUp() async {
    final name = '${_contact?['displayName'] ?? 'them'}';
    final proximity = '${_contact?['proximity'] ?? 'unknown'}';
    final description = switch (proximity) {
      'household' || 'local' => 'Make plans with $name',
      'remote' => 'Call or FaceTime $name',
      _ => 'Reach out to $name',
    };
    final today = widget.session.now.toIso8601String().split('T').first;
    _showResult(
      await widget.session.createRecord('task', {
        'description': description,
        'createdAt': widget.session.now.toIso8601String(),
        'dueAt': today,
        'status': 'today',
        'contactRefs': [widget.contactId],
      }, description: 'added $description to today'),
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
    final proximity = '${contact['proximity'] ?? 'unknown'}';
    final followUpLabel = switch (proximity) {
      'household' => 'Plan time together',
      'local' => 'Plan something',
      'remote' => 'Plan a call',
      _ => 'Add follow-up',
    };
    final introducedBy = widget.session.store['${contact['introducedBy']}'];
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
                    icon: Icon(
                      proximity == 'remote'
                          ? Icons.phone_in_talk_outlined
                          : proximity == 'local' || proximity == 'household'
                          ? Icons.event_available_outlined
                          : Icons.add_task_rounded,
                    ),
                    label: Text(followUpLabel),
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
                title: 'Relationship plan',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Start with a category. You can tune any part afterward.',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final preset in RelationshipPreset.values)
                          ActionChip(
                            key: Key('relationship-preset-${preset.name}'),
                            label: Text(relationshipPresetLabel(preset)),
                            onPressed: () => _setPreset(preset),
                          ),
                      ],
                    ),
                    const Divider(height: 26),
                    const Text('Circle'),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final circle in RelationshipCircle.values)
                          ChoiceChip(
                            key: Key('relationship-circle-${circle.name}'),
                            label: Text(relationshipCircleLabel(circle)),
                            selected: status.circle == circle,
                            onSelected: (_) => _setCircle(circle),
                          ),
                      ],
                    ),
                    const Divider(height: 26),
                    _goalRow(status, meaningful: false),
                    const SizedBox(height: 10),
                    _goalRow(status, meaningful: true),
                    const Divider(height: 26),
                    _descriptorRow(
                      'Roles',
                      ((contact['relationshipRoles'] as List?) ?? const [])
                              .isEmpty
                          ? 'Not set'
                          : (contact['relationshipRoles'] as List).join(', '),
                      _editRoles,
                    ),
                    _descriptorRow(
                      'Proximity',
                      _titleCase('${contact['proximity'] ?? 'unknown'}'),
                      () => _chooseProximity(
                        '${contact['proximity'] ?? 'unknown'}',
                      ),
                    ),
                    _descriptorRow(
                      'Reminders',
                      _engagementLabel(status.engagement),
                      () => _chooseEngagement(status.engagement),
                    ),
                    _descriptorRow(
                      'Introduced by',
                      introducedBy == null
                          ? 'Not set'
                          : '${introducedBy['displayName']}',
                      _chooseIntroducedBy,
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
                                '${_mediumLabel('${interaction['medium'] ?? interaction['kind'] ?? 'interaction'}')} · ${connectionDepthOf(interaction) == ConnectionDepth.meaningful ? 'Meaningful' : 'Quick touch'}',
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
                              onTap: () => _editInteraction(interaction),
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

  Widget _goalRow(RelationshipStatus status, {required bool meaningful}) {
    final target = meaningful
        ? status.meaningfulTargetDays
        : status.touchTargetDays;
    final tracked = meaningful
        ? (_contact?['trackMeaningful'] != false && target != null)
        : (_contact?['trackTouch'] != false && target != null);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meaningful ? 'Meaningful connection' : 'Any contact'),
              Text(
                tracked ? 'Goal every $target days' : 'Not tracked',
                style: const TextStyle(color: PlenaraTheme.quietInk),
              ),
            ],
          ),
        ),
        TextButton(
          key: Key(meaningful ? 'meaningful-goal-edit' : 'touch-goal-edit'),
          onPressed: () => _customGoal(meaningful: meaningful),
          child: Text(tracked ? 'Change' : 'Set'),
        ),
        Switch(
          key: Key(meaningful ? 'meaningful-goal-toggle' : 'touch-goal-toggle'),
          value: tracked,
          onChanged: (value) => _toggleGoal(meaningful: meaningful, on: value),
        ),
      ],
    );
  }

  Widget _descriptorRow(
    String label,
    String value,
    Future<void> Function() onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value),
    trailing: const Icon(Icons.edit_outlined, size: 19),
    onTap: onTap,
  );

  Future<void> _chooseProximity(String selected) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Proximity'),
        children: [
          RadioGroup<String>(
            groupValue: selected,
            onChanged: (choice) => Navigator.pop(context, choice),
            child: Column(
              children: [
                for (final value in const [
                  'household',
                  'local',
                  'remote',
                  'unknown',
                ])
                  RadioListTile<String>(
                    value: value,
                    title: Text(_titleCase(value)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (value != null) await _setProximity(value);
  }

  Future<void> _chooseEngagement(RelationshipEngagement selected) async {
    final value = await showDialog<RelationshipEngagement>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Reminder status'),
        children: [
          RadioGroup<RelationshipEngagement>(
            groupValue: selected,
            onChanged: (choice) => Navigator.pop(context, choice),
            child: Column(
              children: [
                for (final engagement in RelationshipEngagement.values)
                  RadioListTile<RelationshipEngagement>(
                    value: engagement,
                    title: Text(_engagementLabel(engagement)),
                    subtitle: Text(switch (engagement) {
                      RelationshipEngagement.active =>
                        'Goals drive suggestions',
                      RelationshipEngagement.seasonal =>
                        'Keep history; hide goals for now',
                      RelationshipEngagement.paused => 'Pause suggestions',
                      RelationshipEngagement.archived => 'History only',
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (value != null) await _setEngagement(value);
  }

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

class _InteractionDraft {
  final String medium;
  final ConnectionDepth depth;
  final DateTime at;
  final String note;
  const _InteractionDraft(this.medium, this.depth, this.at, this.note);
}

class _InteractionEditor extends StatefulWidget {
  final DateTime now;
  final Map<String, dynamic>? initial;
  const _InteractionEditor({required this.now, this.initial});

  @override
  State<_InteractionEditor> createState() => _InteractionEditorState();
}

class _InteractionEditorState extends State<_InteractionEditor> {
  late String _medium;
  late ConnectionDepth _depth;
  late DateTime _date;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _medium = '${initial?['medium'] ?? 'in_person'}';
    _depth = initial == null
        ? ConnectionDepth.meaningful
        : connectionDepthOf(initial);
    _date = DateTime.tryParse('${initial?['at'] ?? ''}') ?? widget.now;
    _note = TextEditingController(text: '${initial?['note'] ?? ''}');
  }

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
              widget.initial == null
                  ? 'Log an interaction'
                  : 'Edit interaction',
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
                    onSelected: (_) => setState(() {
                      _medium = medium;
                      _depth =
                          const {
                            'in_person',
                            'facetime',
                            'phone',
                          }.contains(medium)
                          ? ConnectionDepth.meaningful
                          : ConnectionDepth.quick;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'What kind of connection was it?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            SegmentedButton<ConnectionDepth>(
              segments: const [
                ButtonSegment(
                  value: ConnectionDepth.quick,
                  icon: Icon(Icons.bolt_outlined),
                  label: Text('Quick touch'),
                ),
                ButtonSegment(
                  value: ConnectionDepth.meaningful,
                  icon: Icon(Icons.favorite_outline),
                  label: Text('Meaningful'),
                ),
              ],
              selected: {_depth},
              onSelectionChanged: (values) =>
                  setState(() => _depth = values.single),
            ),
            const SizedBox(height: 6),
            const Text(
              'Meaningful means a reciprocal, attentive exchange or shared experience that left you more current or connected.',
              style: TextStyle(color: PlenaraTheme.quietInk),
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
                  _InteractionDraft(_medium, _depth, _date, _note.text),
                ),
                child: Text(
                  widget.initial == null
                      ? 'Log interaction'
                      : 'Save interaction',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ImportOrganizer extends StatefulWidget {
  final int count;
  const _ImportOrganizer({required this.count});

  @override
  State<_ImportOrganizer> createState() => _ImportOrganizerState();
}

class _ImportOrganizerState extends State<_ImportOrganizer> {
  RelationshipPreset _preset = RelationshipPreset.contextOnly;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organize ${widget.count == 1 ? 'this person' : '${widget.count} people'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose how Plenara should treat new people. Existing people keep their current plan when contact details refresh.',
              style: TextStyle(color: PlenaraTheme.quietInk),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<RelationshipPreset>(
              key: const Key('import-preset-picker'),
              initialValue: _preset,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final preset in RelationshipPreset.values)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(relationshipPresetLabel(preset)),
                  ),
              ],
              onChanged: (value) => setState(() => _preset = value!),
            ),
            const SizedBox(height: 8),
            Text(
              _presetDescription(_preset),
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('import-organize-save'),
                onPressed: () => Navigator.pop(context, _preset),
                child: Text(
                  widget.count == 1
                      ? 'Import person'
                      : 'Import ${widget.count} people',
                ),
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
    return status?.engagement == RelationshipEngagement.active
        ? 'History only · no contact goals'
        : '${_engagementLabel(status?.engagement ?? RelationshipEngagement.active)} · history only';
  }
  if (status.lastTouchAt == null) {
    return 'No interaction logged · ${_goalSummary(status)}';
  }
  final last = _friendlyDate(_isoDate(status.lastTouchAt!));
  final medium = _mediumLabel(status.lastTouchMedium ?? 'interaction');
  return '$medium · $last · ${_healthTitle(status)}';
}

String _suggestionLine(RelationshipStatus status) {
  final need = status.need == RelationshipNeed.meaningful
      ? 'Meaningful connection due'
      : 'Touch due';
  return '$need · ${relationshipProximityGuidance(status.proximity)}';
}

String _goalSummary(RelationshipStatus status) {
  final goals = <String>[
    if (status.touchTargetDays != null)
      'touch every ${status.touchTargetDays} days',
    if (status.meaningfulTargetDays != null)
      'meaningful every ${status.meaningfulTargetDays} days',
  ];
  return goals.isEmpty ? 'history only' : goals.join(' · ');
}

String _healthTitle(RelationshipStatus status) {
  final meaningful = status.need == RelationshipNeed.meaningful;
  return switch (status.health) {
    RelationshipHealth.untracked => 'History without reminders',
    RelationshipHealth.noHistory =>
      meaningful
          ? 'Ready for a meaningful connection'
          : 'Ready for a first check-in',
    RelationshipHealth.onTrack => 'On track',
    RelationshipHealth.dueSoon =>
      meaningful ? 'Meaningful connection coming due' : 'Contact coming due',
    RelationshipHealth.due =>
      meaningful ? 'Meaningful connection due today' : 'Contact due today',
    RelationshipHealth.overdue =>
      meaningful ? 'Ready for a meaningful connection' : 'Ready to reconnect',
  };
}

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

String _titleCase(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

String _engagementLabel(RelationshipEngagement engagement) =>
    switch (engagement) {
      RelationshipEngagement.active => 'Active',
      RelationshipEngagement.seasonal => 'Seasonal',
      RelationshipEngagement.paused => 'Paused',
      RelationshipEngagement.archived => 'Archived',
    };

String _presetDescription(RelationshipPreset preset) => switch (preset) {
  RelationshipPreset.closeFamily => 'Core · touch 7d · meaningful 14d',
  RelationshipPreset.closeLocalFriend => 'Close · local · 14d / 30d',
  RelationshipPreset.closeRemoteFriend => 'Close · remote · 14d / 30d',
  RelationshipPreset.connectedFriend => 'Keep connected · 30d / 60d',
  RelationshipPreset.oldRemoteFriend => 'Keep warm · remote · touch 90d',
  RelationshipPreset.neighbor => 'Local context · no reminders',
  RelationshipPreset.community => 'Local community · no reminders',
  RelationshipPreset.secondDegree => 'Second-degree · no reminders',
  RelationshipPreset.household => 'Core context · no reminders',
  RelationshipPreset.contextOnly => 'Remember details · no reminders',
};

String _circleCadence(RelationshipCircle circle) {
  final touch = relationshipCircleTouchDays[circle];
  final meaningful = relationshipCircleMeaningfulDays[circle];
  if (touch == null && meaningful == null) return 'History only · no reminders';
  final parts = <String>[
    if (touch != null) 'touch every $touch days',
    if (meaningful != null) 'meaningful every $meaningful days',
  ];
  return parts.join(' · ');
}

String _circleDescription(RelationshipCircle circle) => switch (circle) {
  RelationshipCircle.core =>
    'Your innermost circle. Weekly touch and meaningful connection every two weeks.',
  RelationshipCircle.close =>
    'Important relationships. Touch every two weeks and connect meaningfully each month.',
  RelationshipCircle.connected =>
    'People you actively want in your life. Monthly touch and meaningful connection every two months.',
  RelationshipCircle.warm =>
    'Dormant or distant ties to keep alive with a touch about every three months.',
  RelationshipCircle.context =>
    'People whose details matter, without contact reminders.',
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
