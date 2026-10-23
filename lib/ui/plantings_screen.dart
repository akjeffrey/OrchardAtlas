import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'plants_list.dart';

class PlantingsScreen extends StatefulWidget {
  const PlantingsScreen({super.key});
  @override
  State<PlantingsScreen> createState() => _PlantingsState();
}

class _PlantingsState extends State<PlantingsScreen> {
  PlantLifeCycle lifeCycle = PlantLifeCycle.annual;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Annual & perennial plantings')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<PlantLifeCycle>(
            initialValue: lifeCycle,
            decoration: const InputDecoration(labelText: 'Management'),
            items: [
              for (final value in PlantLifeCycle.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) => setState(() => lifeCycle = value!),
          ),
        ),
        Expanded(child: PlantsList(lifeCycle: lifeCycle, useMapFilters: false)),
      ],
    ),
  );
}
