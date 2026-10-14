import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';

class AddPlantScreen extends ConsumerStatefulWidget {
  const AddPlantScreen({super.key, this.template, this.location});
  final PlantTemplate? template;
  final Coordinates? location;
  @override
  ConsumerState<AddPlantScreen> createState() => _AddPlantState();
}

class _AddPlantState extends ConsumerState<AddPlantScreen> {
  final name = TextEditingController();
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final selected = <String?>[null, null, null, null];
  bool confirmed = false, busy = false, locating = false;
  String? message;
  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      name.text = template.name;
      final path = ref.read(taxonomyProvider).ancestry(template.taxonId);
      for (var i = 0; i < path.length; i++) {
        selected[i] = path[i].id;
      }
    }
    if (widget.location != null) setCoordinates(widget.location!);
  }

  void setCoordinates(Coordinates coordinates) {
    latitude.text = coordinates.latitude.toStringAsFixed(7);
    longitude.text = coordinates.longitude.toStringAsFixed(7);
    confirmed = false;
  }

  @override
  void dispose() {
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted) return;
      setState(() {
        setCoordinates(fix.coordinates);
        message =
            'GPS accuracy ±${fix.accuracyMeters.round()} m. Check coordinates and confirm the plant position.';
      });
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (!confirmed) throw ArgumentError('Confirm this plant’s position');
      final taxonId = selected[3] ?? selected[2];
      if (taxonId == null) {
        throw ArgumentError('Select group, genus and species');
      }
      final position = Coordinates(
        double.parse(latitude.text),
        double.parse(longitude.text),
      );
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final plant = ref
          .read(commandsProvider)
          .addPlant(
            place: place,
            name: name.text,
            taxonId: taxonId,
            location: position,
          );
      context.go('/', extra: plant.location);
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.template == null ? 'Add Plant' : 'Add Another Like This',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.template != null)
            const Text(
              'Taxonomy and name copied. Confirm a new position for this plant.',
            ),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Plant name'),
            maxLength: 500,
          ),
          for (var i = 0; i < 4; i++)
            if (i == 0 || selected[i - 1] != null)
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'taxon-$i-${selected[i]}-${i == 0 ? '' : selected[i - 1]}',
                ),
                initialValue: selected[i],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: [
                    'Group',
                    'Genus',
                    'Species',
                    'Cultivar (optional)',
                  ][i],
                ),
                items: [
                  if (i == 3)
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Unspecified cultivar'),
                    ),
                  for (final t in taxonomy.children(
                    i == 0 ? null : selected[i - 1],
                  ))
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        selected[i] = value == '' ? null : value;
                        for (var j = i + 1; j < 4; j++) {
                          selected[j] = null;
                        }
                      }),
              ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: locating || busy ? null : locate,
            icon: const Icon(Icons.my_location),
            label: Text(locating ? 'Locating…' : 'Use current GPS location'),
          ),
          TextButton(
            onPressed: () =>
                ref.read(locationRepositoryProvider).openSettings(),
            child: const Text('Open location settings'),
          ),
          TextField(
            controller: latitude,
            decoration: const InputDecoration(
              labelText: 'Latitude (−90 to 90)',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (_) => setState(() => confirmed = false),
          ),
          TextField(
            controller: longitude,
            decoration: const InputDecoration(
              labelText: 'Longitude (−180 to 180)',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (_) => setState(() => confirmed = false),
          ),
          CheckboxListTile(
            value: confirmed,
            title: const Text('I confirm this plant’s position'),
            onChanged: (value) => setState(() => confirmed = value ?? false),
          ),
          if (message != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
          FilledButton(
            onPressed: busy || locating ? null : save,
            child: Text(busy ? 'Saving…' : 'Save plant locally'),
          ),
        ],
      ),
    );
  }
}
