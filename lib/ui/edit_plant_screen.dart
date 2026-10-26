import 'orchard_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import 'common.dart';
import 'sections_screen.dart';
import '../domain/models.dart';
import 'classification_picker.dart';
import 'plant_location_picker.dart';

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
      season = TextEditingController(),
      notes = TextEditingController();
  bool initialized = false;
  String? sectionId, taxonId;
  final latitude = TextEditingController(), longitude = TextEditingController();
  String? plantedOn;
  String? error;
  @override
  void dispose() {
    name.dispose();
    rootstock.dispose();
    nursery.dispose();
    season.dispose();
    notes.dispose();
    latitude.dispose();
    longitude.dispose();
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
              taxonId = plant.taxonId;
              plantedOn = plant.plantedOn;
              latitude.text = plant.location.latitude.toString();
              longitude.text = plant.location.longitude.toString();
              name.text = plant.name;
              rootstock.text = plant.rootstock;
              nursery.text = plant.nursery;
              season.text = plant.season ?? '';
              notes.text = plant.notes;
              initialized = true;
            }
            return OrchardForm(
              title: 'Edit plant details',
              subtitle: 'Keep classification, planting information and location up to date.',
              children: [
                const Text('Edit plant details, classification and location.'),
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
                const Text(
                  'Show on Map uses the saved location. Use Back to return to your unsaved edits.',
                ),
                TextField(
                  controller: name,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Plant name'),
                ),
                ClassificationPicker(
                  value: taxonId,
                  onChanged: (id) => setState(() => taxonId = id),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Text('Pick location on map'),
                  onPressed: () async {
                    // Invalid manual input must not prevent opening the picker.
                    Coordinates initialLocation = plant.location;
                    try {
                      initialLocation = Coordinates(
                        double.parse(latitude.text),
                        double.parse(longitude.text),
                      );
                    } on ArgumentError {
                      // Fall back to the saved location.
                    } on FormatException {
                      // Fall back to the saved location.
                    }
                    final location = await Navigator.of(context)
                        .push<Coordinates>(
                          MaterialPageRoute(
                            builder: (_) => PlantLocationPicker(
                              initialLocation: initialLocation,
                            ),
                          ),
                        );
                    if (location == null || !mounted) return;
                    setState(() {
                      latitude.text = location.latitude.toString();
                      longitude.text = location.longitude.toString();
                    });
                  },
                ),
                TextField(
                  controller: latitude,
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
                TextField(
                  controller: longitude,
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
                ListTile(
                  title: const Text('Planting date'),
                  subtitle: Text(plantedOn ?? 'Not recorded'),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: plantedOn == null
                          ? DateTime.now()
                          : parseCalendarDate(plantedOn!),
                      firstDate: DateTime(1800),
                      lastDate: DateTime(2100),
                    );
                    if (date != null && mounted) {
                      setState(() => plantedOn = calendarDate(date));
                    }
                  },
                  trailing: IconButton(
                    tooltip: 'Clear planting date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => plantedOn = null),
                  ),
                ),
                if (plant.lifeCycle == PlantLifeCycle.annual)
                  TextField(
                    controller: season,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Season / year',
                    ),
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
                      if (taxonId == null ||
                          !ref
                              .read(taxonomyProvider)
                              .isPlantIdentity(taxonId!)) {
                        throw ArgumentError('Select a Variety');
                      }
                      ref
                          .read(orchardRepositoryProvider)
                          .updatePlant(
                            plant.copyWith(
                              name: name.text,
                              taxonId: taxonId,
                              location: Coordinates(
                                double.parse(latitude.text),
                                double.parse(longitude.text),
                              ),
                              plantedOn: plantedOn,
                              clearPlantedOn: plantedOn == null,
                              clearAccuracy:
                                  latitude.text !=
                                      plant.location.latitude.toString() ||
                                  longitude.text !=
                                      plant.location.longitude.toString(),
                              clearRowOrder: sectionId != plant.sectionId,
                              rootstock: rootstock.text,
                              season: plant.lifeCycle == PlantLifeCycle.annual
                                  ? season.text.trim()
                                  : plant.season,
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
