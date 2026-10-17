import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'events_table.dart';
import 'tasks_screen.dart';
import 'common.dart';

class ClassificationScreen extends ConsumerStatefulWidget {
  const ClassificationScreen({super.key});
  @override
  ConsumerState<ClassificationScreen> createState() => _ClassificationState();
}

class _ClassificationState extends ConsumerState<ClassificationScreen> {
  String selected = '';
  int year = DateTime.now().year;
  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider);
    final ids = selected.isEmpty ? null : taxonomy.descendants(selected);
    final plants =
        (ref.watch(plantsProvider).asData?.value.value ?? <ManagedPlant>[])
            .where((p) => ids == null || ids.contains(p.taxonId))
            .toList();
    final plantIds = plants.map((p) => p.id).toSet();
    final events = ref.watch(allEventsProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(title: const Text('Group / Type / Variety')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Group, Type or Variety',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All classifications'),
                  ),
                  for (final t in taxonomy.taxa)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        taxonomy.ancestry(t.id).map((a) => a.name).join(' › '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => selected = id!),
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Plants'),
                Tab(text: 'Tasks'),
                Tab(text: 'Activities'),
                Tab(text: 'Harvests'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    children: [
                      for (final p in plants)
                        ListTile(
                          title: Text(p.name),
                          subtitle: Text(p.status.name),
                          onTap: () => context.push('/plants/${p.id}'),
                        ),
                    ],
                  ),
                  TasksPane(
                    key: ValueKey('tasks-$selected'),
                    taxonId: selected.isEmpty ? null : selected,
                  ),
                  events.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorPanel(e),
                    data: (all) => SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: EventsTable(
                        events: all
                            .where((e) => plantIds.contains(e.itemId))
                            .toList(),
                        names: {for (final p in plants) p.id: p.name},
                      ),
                    ),
                  ),
                  events.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorPanel(e),
                    data: (all) {
                      final cropIds =
                          (ref.watch(cropsProvider).asData?.value.value ?? [])
                              .where(
                                (c) => ids == null || ids.contains(c.taxonId),
                              )
                              .map((c) => c.id)
                              .toSet();
                      final harvests = all
                          .where(
                            (e) =>
                                plantIds.contains(e.itemId) &&
                                e.type == ActivityType.harvest &&
                                parseCalendarDate(e.activityDate).year == year,
                          )
                          .toList();
                      final crops =
                          (ref
                                      .watch(cropHarvestsProvider)
                                      .asData
                                      ?.value
                                      .value ??
                                  [])
                              .where(
                                (h) =>
                                    cropIds.contains(h.cropId) &&
                                    parseCalendarDate(h.activityDate).year ==
                                        year,
                              )
                              .toList();
                      final totals = Map<HarvestUnit, double>.of(
                        harvestByUnit(harvests, year),
                      );
                      for (final h in crops) {
                        totals[h.harvest.unit] =
                            (totals[h.harvest.unit] ?? 0) + h.harvest.quantity;
                      }
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () => setState(() => year--),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text('$year harvests'),
                              IconButton(
                                onPressed: () => setState(() => year++),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          for (final total in totals.entries)
                            ListTile(
                              title: Text(
                                '${total.value.toStringAsFixed(total.key == HarvestUnit.count ? 0 : 3)} ${total.key.name}',
                              ),
                            ),
                          if (totals.isEmpty)
                            const Text(
                              'No harvests for this classification and year.',
                            ),
                          EventsTable(
                            events: harvests,
                            names: {for (final p in plants) p.id: p.name},
                          ),
                          for (final h in crops)
                            ListTile(
                              title: Text(
                                '${h.harvest.quantity} ${h.harvest.unit.name} · ${h.activityDate}',
                              ),
                              subtitle: Text(h.notes),
                              onTap: () => context.push('/crops/${h.cropId}'),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
