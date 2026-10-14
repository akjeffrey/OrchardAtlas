import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';

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
              Text(
                '${plant.location.latitude.toStringAsFixed(7)}, ${plant.location.longitude.toStringAsFixed(7)}',
              ),
              SyncStatus(snapshot),
              FilledButton.icon(
                onPressed: () => context.push('/plants/${plant.id}/activity'),
                icon: const Icon(Icons.edit_note),
                label: const Text('Record Activity / Harvest'),
              ),
              OutlinedButton(
                onPressed: () =>
                    context.push('/plants/new', extra: plant.template),
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
                  final totals = HarvestTotals.forYear(history.value, year);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${totals.kilograms.toStringAsFixed(3)} kg · ${totals.count.toStringAsFixed(0)} count',
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
                      for (final event in history.value)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${activityLabel(event.type.name)} · ${event.activityDate}',
                          ),
                          subtitle: Text(
                            [
                              if (event.harvest != null)
                                '${event.harvest!.quantity} ${event.harvest!.unit.name}',
                              if (event.notes.isNotEmpty) event.notes,
                            ].join('\n'),
                          ),
                        ),
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
