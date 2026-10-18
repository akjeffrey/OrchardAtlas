import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'orchard_map.dart';

/// Returns a draft location; only the plant editor persists the user's changes.
class PlantLocationPicker extends StatefulWidget {
  const PlantLocationPicker({super.key, required this.initialLocation});

  final Coordinates initialLocation;

  @override
  State<PlantLocationPicker> createState() => _PlantLocationPickerState();
}

class _PlantLocationPickerState extends State<PlantLocationPicker> {
  late Coordinates selected = widget.initialLocation;

  void select(Coordinates location) => setState(() => selected = location);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pick plant location')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Tap a new spot or drag the pin to move this plant.'),
        ),
        Expanded(
          child: OrchardMap(
            center: widget.initialLocation,
            selected: selected,
            onTap: select,
            onSelectedMoved: select,
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                '${selected.latitude.toStringAsFixed(6)}, '
                '${selected.longitude.toStringAsFixed(6)}',
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(selected),
                    child: const Text('Use this location'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
