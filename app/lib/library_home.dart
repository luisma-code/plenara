import 'package:flutter/material.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';

import 'plenara_theme.dart';

class LibraryHome extends StatelessWidget {
  final Session session;
  final VoidCallback? onVoice;
  final void Function(String title, Set<String>? typeIds) onOpen;

  const LibraryHome({
    super.key,
    required this.session,
    required this.onOpen,
    this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    session.setPlannerContext(const PlannerContext());
    final groups = _groups(session);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
            key: const Key('library-home'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 68, 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LIBRARY',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: PlenaraTheme.amber,
                                    letterSpacing: 2.2,
                                  ),
                            ),
                            Text(
                              'The people and practices you’re building',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w300),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Talk to Plena',
                        onPressed: onVoice,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 200,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Card(
                      child: InkWell(
                        key: Key('library-${group.id}'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => onOpen(group.title, group.typeIds),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(group.icon, color: PlenaraTheme.amber),
                                  const Spacer(),
                                  Text(
                                    '${group.count}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w300),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                group.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                group.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PlenaraTheme.quietInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryGroup {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int count;
  final Set<String>? typeIds;

  const _LibraryGroup({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.count,
    required this.typeIds,
  });
}

List<_LibraryGroup> _groups(Session session) {
  int count(Set<String> types) => session.store.values
      .where((record) => types.contains(record['typeId']))
      .length;
  const people = {
    'contact',
    'contact_fact',
    'contact_relationship',
    'contact_date',
    'interaction',
  };
  const routines = {'routine', 'routine_step', 'routine_session'};
  const projects = {'project', 'area'};
  final trackerTypes = <String>{
    for (final entry in session.types.entries)
      if (((entry.value['attributes'] as List?) ?? const [])
          .whereType<Map>()
          .any(
            (attribute) =>
                attribute['valueType'] == 'number' ||
                attribute['valueType'] == 'decimal',
          ))
        entry.key,
  };
  return [
    _LibraryGroup(
      id: 'people',
      title: 'People',
      description: 'Relationships, facts, dates, and recent interactions',
      icon: Icons.people_outline_rounded,
      count: count(people),
      typeIds: people,
    ),
    _LibraryGroup(
      id: 'goals',
      title: 'Goals',
      description: 'Longer arcs and the progress connected to them',
      icon: Icons.flag_outlined,
      count: count(const {'goal'}),
      typeIds: const {'goal'},
    ),
    _LibraryGroup(
      id: 'routines',
      title: 'Routines',
      description: 'Reusable practices and completed sessions',
      icon: Icons.self_improvement_rounded,
      count: count(routines),
      typeIds: routines,
    ),
    _LibraryGroup(
      id: 'trackers',
      title: 'Trackers',
      description: 'Movement, mood, meals, and authored measurements',
      icon: Icons.monitor_heart_outlined,
      count: count(trackerTypes),
      typeIds: trackerTypes,
    ),
    _LibraryGroup(
      id: 'journal',
      title: 'Journal',
      description: 'Notes and moments kept in your own words',
      icon: Icons.auto_stories_outlined,
      count: count(const {'journal_entry'}),
      typeIds: const {'journal_entry'},
    ),
    _LibraryGroup(
      id: 'projects',
      title: 'Projects & areas',
      description: 'The commitments and parts of life tasks belong to',
      icon: Icons.account_tree_outlined,
      count: count(projects),
      typeIds: projects,
    ),
    _LibraryGroup(
      id: 'phrases',
      title: 'Learned phrases',
      description: 'The language Plenara has learned from your corrections',
      icon: Icons.record_voice_over_outlined,
      count: session.learnedFlows.length,
      typeIds: null,
    ),
    _LibraryGroup(
      id: 'automations',
      title: 'Automations',
      description: 'Scheduled checks, deliveries, and held writes',
      icon: Icons.bolt_outlined,
      count: session.automations.statuses.length,
      typeIds: null,
    ),
    _LibraryGroup(
      id: 'all',
      title: 'All data',
      description: 'The complete editable archetype browser',
      icon: Icons.grid_view_rounded,
      count: session.store.length,
      typeIds: null,
    ),
  ];
}
