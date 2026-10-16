import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/filters.dart';

final plantFilterProvider = StateProvider<PlantFilter>(
  (ref) => const PlantFilter(),
);

class PlantFilterBar extends ConsumerStatefulWidget {
  const PlantFilterBar({super.key});
  @override
  ConsumerState<PlantFilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<PlantFilterBar> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(plantFilterProvider);
    if (search.text != filter.query) search.text = filter.query;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Search plants',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  ref.read(plantFilterProvider.notifier).state = PlantFilter(
                    query: value,
                    taxonId: filter.taxonId,
                    year: filter.year,
                    status: filter.status,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Filter plants',
            icon: const Icon(Icons.filter_list),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const PlantFilterSheet(),
            ),
          ),
          IconButton(
            tooltip: 'Reset plant filters',
            icon: const Icon(Icons.filter_alt_off),
            onPressed: () => ref.read(plantFilterProvider.notifier).state =
                const PlantFilter(),
          ),
        ],
      ),
    );
  }
}

class PlantFilterSheet extends ConsumerWidget {
  const PlantFilterSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(plantFilterProvider);
    final taxonomy = ref.watch(taxonomyProvider);
    final years =
        (ref.watch(plantsProvider).valueOrNull?.value ?? <ManagedPlant>[])
            .where((p) => p.plantedOn != null)
            .map((p) => parseCalendarDate(p.plantedOn!).year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plant filters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'The map and plant list use the same filters. Parent classifications include every descendant.',
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('filter-taxon-${filter.taxonId}'),
                initialValue: filter.taxonId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Classification'),
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
                onChanged: (value) =>
                    ref.read(plantFilterProvider.notifier).state = PlantFilter(
                      query: filter.query,
                      taxonId: value == '' ? null : value,
                      year: filter.year,
                      status: filter.status,
                    ),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('filter-year-${filter.year}'),
                initialValue: filter.year?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Planting year'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All years / unknown'),
                  ),
                  for (final year in years)
                    DropdownMenuItem(value: '$year', child: Text('$year')),
                ],
                onChanged: (value) =>
                    ref.read(plantFilterProvider.notifier).state = PlantFilter(
                      query: filter.query,
                      taxonId: filter.taxonId,
                      year: value == '' ? null : int.parse(value!),
                      status: filter.status,
                    ),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('filter-status-${filter.status}'),
                initialValue: filter.status?.name ?? 'all',
                decoration: const InputDecoration(labelText: 'Plant status'),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All statuses'),
                  ),
                  for (final status in ItemStatus.values)
                    DropdownMenuItem(
                      value: status.name,
                      child: Text(status.name),
                    ),
                ],
                onChanged: (value) =>
                    ref.read(plantFilterProvider.notifier).state = PlantFilter(
                      query: filter.query,
                      taxonId: filter.taxonId,
                      year: filter.year,
                      status: value == 'all'
                          ? null
                          : ItemStatus.values.byName(value!),
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Show results'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
