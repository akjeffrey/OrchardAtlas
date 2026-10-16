import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import 'common.dart';
import 'sections_screen.dart';

class EditPlantScreen extends ConsumerStatefulWidget {
  const EditPlantScreen(this.itemId, {super.key});
  final String itemId;
  @override
  ConsumerState<EditPlantScreen> createState() => _EditState();
}

class _EditState extends ConsumerState<EditPlantScreen> {
  final name = TextEditingController(),
      rootstock = TextEditingController(),
      nursery = TextEditingController(),
      notes = TextEditingController();
  bool initialized = false;
  String? sectionId;
  String? error;
  @override
  void dispose() {
    name.dispose();
    rootstock.dispose();
    nursery.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit plant')),
    body: ref
        .watch(plantsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(e),
          data: (snapshot) {
            final plant = snapshot.value
                .where((p) => p.id == widget.itemId)
                .firstOrNull;
            if (plant == null) return const ErrorPanel('Plant unavailable');
            if (!initialized) {
              sectionId = plant.sectionId;
              name.text = plant.name;
              rootstock.text = plant.rootstock;
              nursery.text = plant.nursery;
              notes.text = plant.notes;
              initialized = true;
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Edit plant metadata. Recorded activities, planting date and captured position are preserved.',
                ),
                TextField(
                  controller: name,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Plant name'),
                ),
                SectionPicker(
                  value: sectionId,
                  onChanged: (id) => setState(() => sectionId = id),
                ),
                TextField(
                  controller: rootstock,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Rootstock'),
                ),
                TextField(
                  controller: nursery,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Nursery / source',
                  ),
                ),
                TextField(
                  controller: notes,
                  maxLength: 10000,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (error != null) Text(error!),
                FilledButton(
                  onPressed: () {
                    try {
                      // Use the latest stream value so a simultaneous archive is preserved.
                      ref
                          .read(orchardRepositoryProvider)
                          .updatePlant(
                            plant.copyWith(
                              name: name.text,
                              rootstock: rootstock.text,
                              nursery: nursery.text,
                              notes: notes.text,
                              sectionId: sectionId,
                              clearSection: sectionId == null,
                            ),
                          );
                      context.go('/plants/${plant.id}');
                    } catch (e) {
                      setState(() => error = '$e');
                    }
                  },
                  child: const Text('Save changes'),
                ),
              ],
            );
          },
        ),
  );
}
