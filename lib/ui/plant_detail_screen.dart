import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/models.dart';
import 'common.dart';
import 'events_table.dart';
import 'delete_actions.dart';
import 'life_cycle_button.dart';
import 'photos_panel.dart';

class PlantDetailScreen extends ConsumerStatefulWidget {
  const PlantDetailScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<PlantDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<PlantDetailScreen> {
  int year = DateTime.now().year;
  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider);
    final events = ref.watch(eventsProvider(widget.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Detail'),
        leading: IconButton(
          tooltip: 'Back to map',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: plants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorPanel(e, retry: () => ref.invalidate(plantsProvider)),
        data: (snapshot) {
          final matches = snapshot.value.where((p) => p.id == widget.id);
          if (matches.isEmpty) {
            return ErrorPanel(
              'Plant unavailable in cache. Reconnect or check access.',
              retry: () => ref.invalidate(plantsProvider),
            );
          }
          final plant = matches.first;
          final taxonomy = ref.watch(taxonomyProvider);
          final path = taxonomy.taxa.any((t) => t.id == plant.taxonId)
              ? taxonomy.ancestry(plant.taxonId).map((t) => t.name).join(' › ')
              : 'Unknown taxon (${plant.taxonId})';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                plant.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(path),
              OutlinedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('Show on Map'),
                onPressed: () {
                  if (plant.status == ItemStatus.archived) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Restore this archived plant before showing it on the map.',
                        ),
                      ),
                    );
                    return;
                  }
                  context.push('/?plant=${plant.id}', extra: plant.location);
                },
              ),
              PhotosPanel(plant.id),
              Text('Status: ${plant.status.name}'),
              Text(
                'Management: ${plant.lifeCycle.name}${plant.season == null ? '' : ' · ${plant.season}'}',
              ),
              LifeCycleButton(plant: plant),
              if (plant.sectionId != null)
                TextButton(
                  onPressed: () => context.push('/sections/${plant.sectionId}'),
                  child: Text(
                    'Area / row: ${ref.watch(sectionsProvider).valueOrNull?.value.where((s) => s.id == plant.sectionId).firstOrNull?.name ?? plant.sectionId}',
                  ),
                ),
              Text('Planting date: ${plant.plantedOn ?? 'Not recorded'}'),
              if (plant.rootstock.isNotEmpty)
                Text('Rootstock: ${plant.rootstock}'),
              if (plant.nursery.isNotEmpty)
                Text('Nursery / source: ${plant.nursery}'),
              if (plant.notes.isNotEmpty) Text(plant.notes),
              if (plant.accuracyMeters != null)
                Text(
                  'Captured GPS accuracy: ±${plant.accuracyMeters!.round()} m',
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: ref.watch(viewOnlyOrchardProvider)
                        ? null
                        : () =>
                              deletePlantWithConfirmation(context, ref, plant),
                    child: const Text('Delete permanently'),
                  ),
                  TextButton.icon(
                    onPressed: ref.watch(viewOnlyOrchardProvider)
                        ? null
                        : () => context.push('/plants/${plant.id}/edit'),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit plant'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/plants/${plant.id}/tasks'),
                    icon: const Icon(Icons.checklist),
                    label: const Text('Plant tasks'),
                  ),
                  TextButton(
                    onPressed: ref.watch(viewOnlyOrchardProvider)
                        ? null
                        : () async {
                            final archive = plant.status == ItemStatus.active;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  archive ? 'Archive plant?' : 'Restore plant?',
                                ),
                                content: const Text(
                                  'History and tasks are retained. Archived plants never show on the map; find them in Archived Plants.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(
                                      archive ? 'Archive' : 'Restore',
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              try {
                                ref
                                    .read(orchardRepositoryProvider)
                                    .updatePlant(
                                      plant.copyWith(
                                        status: archive
                                            ? ItemStatus.archived
                                            : ItemStatus.active,
                                      ),
                                    );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              }
                            }
                          },
                    child: Text(
                      plant.status == ItemStatus.active
                          ? 'Archive plant'
                          : 'Restore plant',
                    ),
                  ),
                ],
              ),
              Text(
                '${plant.location.latitude.toStringAsFixed(7)}, ${plant.location.longitude.toStringAsFixed(7)}',
              ),
              SyncStatus(snapshot),
              FilledButton.icon(
                onPressed: ref.watch(viewOnlyOrchardProvider)
                    ? null
                    : () => context.push('/plants/${plant.id}/activity'),
                icon: const Icon(Icons.edit_note),
                label: const Text('Record Activity / Harvest'),
              ),
              OutlinedButton(
                onPressed: ref.watch(viewOnlyOrchardProvider)
                    ? null
                    : () async {
                        try {
                          final history = await ref.read(
                            eventsProvider(plant.id).future,
                          );
                          if (context.mounted) {
                            context.push(
                              '/plants/new',
                              extra: plant.templateWithHistory(history.value),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                child: const Text('Add Another Like This'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous year',
                    onPressed: year > 1900
                        ? () => setState(() => year--)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '$year harvest',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    tooltip: 'Next year',
                    onPressed: year < 2100
                        ? () => setState(() => year++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              events.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorPanel(
                  e,
                  retry: () => ref.invalidate(eventsProvider(widget.id)),
                ),
                data: (history) {
                  final totals = harvestByUnit(history.value, year);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        totals.isEmpty
                            ? 'No harvest recorded for $year'
                            : [
                                for (final unit in HarvestUnit.values)
                                  if (totals.containsKey(unit))
                                    '${totals[unit]!.toStringAsFixed(unit == HarvestUnit.count ? 0 : 3)} ${unit.name}',
                              ].join(' · '),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SyncStatus(history),
                      const Divider(),
                      Text(
                        'Activity history',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (history.value.isEmpty)
                        const Text('No cached activities yet.'),
                      EventsTable(events: history.value),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
