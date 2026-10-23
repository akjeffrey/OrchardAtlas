import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';

class LifeCycleButton extends ConsumerWidget {
  const LifeCycleButton({super.key, this.plant, this.crop})
    : assert((plant == null) != (crop == null));
  final ManagedPlant? plant;
  final CropPlanting? crop;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = plant?.lifeCycle ?? crop!.lifeCycle;
    final next = current == PlantLifeCycle.annual
        ? PlantLifeCycle.perennial
        : PlantLifeCycle.annual;
    return OutlinedButton.icon(
      icon: const Icon(Icons.swap_horiz),
      label: Text('Convert to ${next.name}'),
      onPressed: () async {
        var season = plant?.season ?? crop?.season ?? '${DateTime.now().year}';
        String? error;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text('Convert to ${next.name}?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Keep this planting, its location, history, harvests and task links. Existing completed seasons and archive status stay unchanged.',
                  ),
                  if (plant != null && next == PlantLifeCycle.annual)
                    TextFormField(
                      initialValue: season,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: 'Season / year',
                        errorText: error,
                      ),
                      onChanged: (value) => season = value,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      if (next == PlantLifeCycle.annual) {
                        requiredText(season, 'Season');
                      }
                      Navigator.pop(context, true);
                    } catch (_) {
                      update(() => error = 'Enter a season / year');
                    }
                  },
                  child: const Text('Convert'),
                ),
              ],
            ),
          ),
        );
        if (confirmed != true || !context.mounted) return;
        try {
          final orchard = await ref.read(placeProvider.future);
          if (!context.mounted) return;
          if (orchard.id != (plant?.propertyId ?? crop!.propertyId)) {
            throw StateError('Orchard changed; try again');
          }
          final repository = ref.read(orchardRepositoryProvider);
          if (plant != null) {
            final latest = (await ref.read(plantsProvider.future)).value
                .firstWhere((p) => p.id == plant!.id);
            if (!context.mounted) return;
            if (latest.propertyId != orchard.id ||
                (await ref.read(placeProvider.future)).id != orchard.id) {
              throw StateError('Orchard changed; try again');
            }
            if (latest.lifeCycle == next) return;
            repository.updatePlant(
              latest.copyWith(
                lifeCycle: next,
                season: next == PlantLifeCycle.annual
                    ? season.trim()
                    : latest.season,
              ),
            );
          } else {
            final latest = (await ref.read(cropsProvider.future)).value
                .firstWhere((c) => c.id == crop!.id);
            if (!context.mounted) return;
            if (latest.propertyId != orchard.id ||
                (await ref.read(placeProvider.future)).id != orchard.id) {
              throw StateError('Orchard changed; try again');
            }
            if (latest.lifeCycle == next) return;
            repository.saveCrop(latest.withLifeCycle(next));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not convert planting: $e')),
            );
          }
        }
      },
    );
  }
}
