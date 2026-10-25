import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/extensions.dart';
import '../domain/yield_report.dart';
import '../domain/models.dart';
import '../data/event_revision_codec.dart';
import 'classification_picker.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<ReportsScreen> {
  int year = DateTime.now().year;
  String? taxon;
  bool monthly = false;
  @override
  Widget build(BuildContext context) {
    final events = ref.watch(allEventsProvider),
        plants = ref.watch(plantsProvider),
        crops = ref.watch(cropsProvider),
        harvests = ref.watch(cropHarvestsProvider);
    final error = events.error ?? plants.error ?? crops.error ?? harvests.error;
    final loaded =
        events.hasValue &&
        plants.hasValue &&
        crops.hasValue &&
        harvests.hasValue;
    final rows = loaded
        ? yieldRows(
            events.value!,
            plants.value!.value,
            harvests.value!.value,
            crops.value!.value,
          )
        : <YieldRow>[];
    final taxonomy = ref.watch(taxonomyProvider);
    final selected = taxon == null ? null : taxonomy.descendants(taxon!);
    final filtered = rows
        .where(
          (r) =>
              parseCalendarDate(r.date).year == year &&
              (selected == null || selected.contains(r.taxonId)),
        )
        .toList();
    final totals = summarizeYield(
      rows,
      taxonomy,
      year: year,
      taxonId: taxon,
      monthly: monthly,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Harvest reports & recovery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$year harvest'),
              IconButton(
                onPressed: () => setState(() => year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          ClassificationPicker(
            value: taxon,
            allowAny: true,
            allowCreate: false,
            onChanged: (v) => setState(() => taxon = v),
          ),
          SwitchListTile(
            title: const Text('Group by month'),
            value: monthly,
            onChanged: (v) => setState(() => monthly = v),
          ),
          if (error != null) Text('$error'),
          if (!loaded && error == null) const LinearProgressIndicator(),
          Text(
            'Mass is converted to kg. Counts stay separate. Totals are derived from current harvest records, including historical plantings.',
          ),
          for (final row in totals.entries)
            ListTile(
              title: Text(row.key),
              subtitle: Text(
                '${row.value.kilograms.toStringAsFixed(3)} kg · ${row.value.count.toStringAsFixed(0)} count',
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy filtered CSV'),
            onPressed: !loaded
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: yieldCsv(filtered)),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV copied')),
                      );
                    }
                  },
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ActivityRecoveryScreen(),
              ),
            ),
            child: const Text('Activity revisions & recovery'),
          ),
        ],
      ),
    );
  }
}

class ActivityRecoveryScreen extends ConsumerWidget {
  const ActivityRecoveryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Activity revisions & recovery')),
    body: ref
        .watch(recordsProvider(RecordKind.activityRevision))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (records) {
            final sorted = [...records]
              ..sort(
                (a, b) => (b['changedAt'] as String).compareTo(
                  a['changedAt'] as String,
                ),
              );
            return ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Prior activity snapshots are immutable. Restore explicitly replaces the current activity; linked task completion is restored with it. Permanently deleted plants cannot be recovered here.',
                  ),
                ),
                for (final r in sorted)
                  ListTile(
                    title: Text(
                      '${r['action']} · ${(r['event'] as Map)['type']}',
                    ),
                    subtitle: Text(
                      '${r['changedAt']}\n${(r['event'] as Map)['notes']}',
                    ),
                    trailing: ref.watch(canEditOrchardProvider)
                        ? TextButton(
                            child: const Text('Restore'),
                            onPressed: () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Restore this revision?'),
                                  content: const Text(
                                    'This will replace the current activity and change harvest totals if applicable.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Restore'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes != true) return;
                              try {
                                final orchard = await ref.read(
                                  placeProvider.future,
                                );
                                final event = EventRevisionCodec.read(
                                  orchard.id,
                                  r,
                                );
                                final plants = await ref.read(
                                  plantsProvider.future,
                                );
                                if (!plants.value.any(
                                  (p) => p.id == event.itemId,
                                )) {
                                  throw StateError('Plant permanently deleted');
                                }
                                final repo = ref.read(
                                  orchardRepositoryProvider,
                                );
                                final current = await ref.read(
                                  eventsProvider(event.itemId).future,
                                );
                                final exists = current.value.any(
                                  (e) => e.id == event.id,
                                );
                                final restored = exists
                                    ? event
                                    : PlantEvent(
                                        id: event.id,
                                        propertyId: event.propertyId,
                                        itemId: event.itemId,
                                        authorId: ref
                                            .read(userProvider)
                                            .value!
                                            .id,
                                        type: event.type,
                                        occurredAt: event.occurredAt,
                                        activityDate: event.activityDate,
                                        recordedAt: event.recordedAt,
                                        notes: event.notes,
                                        harvest: event.harvest,
                                        taskId: event.taskId,
                                      );
                                if (current.value.any(
                                  (e) => e.id == event.id,
                                )) {
                                  repo.updateEvent(event);
                                } else if (event.taskId != null) {
                                  final tasks = await ref.read(
                                    tasksProvider.future,
                                  );
                                  final task = tasks.value
                                      .where((t) => t.id == event.taskId)
                                      .firstOrNull;
                                  if (task == null) {
                                    throw StateError('Linked task unavailable');
                                  }
                                  repo.saveTaskWithEvent(
                                    task.withStatus(TaskStatus.completed),
                                    restored,
                                  );
                                } else {
                                  repo.appendEvent(restored);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Revision restored'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              }
                            },
                          )
                        : null,
                  ),
                if (sorted.isEmpty)
                  const ListTile(
                    title: Text('No edited or deleted activity revisions yet.'),
                  ),
              ],
            );
          },
        ),
  );
}
