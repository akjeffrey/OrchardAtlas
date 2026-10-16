import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';

Future<void> _confirm(
  BuildContext context,
  String name,
  String detail,
  Future<void> Function() remove,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Permanently delete $name?'),
      content: Text(
        '$detail\nThis cannot be undone. Cloud deletion requires a connection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await remove();
    if (context.mounted) context.go('/');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deletion did not finish: $e. Reconnect and retry.'),
        ),
      );
    }
  }
}

Future<void> deletePlantWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  ManagedPlant plant,
) => _confirm(
  context,
  plant.name,
  'Removes this plant and all its activities, harvests, task assignments, completion records and associated photos.',
  () => ref
      .read(orchardRepositoryProvider)
      .deletePlant(plant.propertyId, plant.id),
);
Future<void> deleteSectionWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  OrchardSection section,
) {
  final sections =
      ref.read(sectionsProvider).valueOrNull?.value ?? <OrchardSection>[];
  final ids = sectionDescendants(section.id, sections);
  final plants =
      ref
          .read(plantsProvider)
          .valueOrNull
          ?.value
          .where((p) => ids.contains(p.sectionId))
          .length ??
      0;
  final crops =
      ref
          .read(cropsProvider)
          .valueOrNull
          ?.value
          .where((c) => ids.contains(c.sectionId))
          .length ??
      0;
  return _confirm(
    context,
    section.name,
    'Removes ${ids.length} Area/Row shapes, $plants cached plants, $crops cached crop records, and all associated activities, harvests, photos and task assignments. Any additional cloud records in this location are also removed.',
    () => ref
        .read(orchardRepositoryProvider)
        .deleteSection(section.propertyId, section.id),
  );
}
