import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/plant_entries.dart';
import '../application/providers.dart';
import '../domain/filters.dart';
import '../domain/models.dart';
import 'common.dart';
import 'icon_picker.dart';

class PlantsList extends ConsumerWidget {
  const PlantsList({super.key, this.lifeCycle, this.useMapFilters = true});
  final PlantLifeCycle? lifeCycle;
  final bool useMapFilters;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxonomy = ref.watch(taxonomyProvider);
    final sections = ref.watch(sectionsProvider).valueOrNull?.value ?? [];
    final filter = useMapFilters
        ? ref.watch(plantFilterProvider)
        : const PlantFilter(status: null);
    return ref
        .watch(plantEntriesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(
            e,
            retry: () {
              ref.invalidate(cropsProvider);
              ref.invalidate(sectionsProvider);
              ref.invalidate(plantsProvider);
            },
          ),
          data: (entries) {
            final matches = filter
                .apply(
                  entries.map((e) => e.plant),
                  taxonomy,
                  sections: sections,
                )
                .toSet();
            final visible = entries
                .where(
                  (e) =>
                      (lifeCycle == null || e.plant.lifeCycle == lifeCycle) &&
                      matches.contains(e.plant),
                )
                .toList();
            if (visible.isEmpty) {
              return const Center(
                child: Text('No plants match. Add a plant or reset filters.'),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final entry = visible[i], p = entry.plant;
                final appearance = taxonomy.taxa.any((t) => t.id == p.taxonId)
                    ? taxonomy.iconFor(p.taxonId)
                    : null;
                return ListTile(
                  leading: IconPreview(
                    symbol: appearance?.symbol,
                    customIconId: appearance?.customIconId,
                    size: 28,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.lifeCycle.name}${p.season == null ? '' : ' · ${p.season}'} · ${p.location.latitude.toStringAsFixed(6)}, ${p.location.longitude.toStringAsFixed(6)}',
                  ),
                  onTap: () => context.push(
                    entry.cropRecord ? '/crops/${p.id}' : '/plants/${p.id}',
                  ),
                );
              },
            );
          },
        );
  }
}
