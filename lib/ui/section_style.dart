import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'plant_symbols.dart';

class SectionStyleFields extends StatelessWidget {
  const SectionStyleFields({
    super.key,
    required this.color,
    required this.symbol,
    required this.onColor,
    required this.onSymbol,
  });
  final int color;
  final PlantSymbol? symbol;
  final ValueChanged<int> onColor;
  final ValueChanged<PlantSymbol?> onSymbol;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<int>(
        initialValue: color,
        decoration: const InputDecoration(labelText: 'Map color'),
        items: [
          for (final entry in {
            0xff4caf50: 'Green',
            0xff2196f3: 'Blue',
            0xffff9800: 'Orange',
            0xfff44336: 'Red',
            0xff9c27b0: 'Purple',
            0xffffeb3b: 'Yellow',
            0xff795548: 'Brown',
          }.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Row(
                children: [
                  Icon(Icons.circle, color: Color(entry.key)),
                  const SizedBox(width: 8),
                  Text(entry.value),
                ],
              ),
            ),
          if (![
            0xff4caf50,
            0xff2196f3,
            0xffff9800,
            0xfff44336,
            0xff9c27b0,
            0xffffeb3b,
            0xff795548,
          ].contains(color))
            DropdownMenuItem(value: color, child: const Text('Saved color')),
        ],
        onChanged: (c) => onColor(c!),
      ),
      DropdownButtonFormField<String>(
        initialValue: symbol?.name ?? '',
        decoration: const InputDecoration(labelText: 'Center icon (optional)'),
        items: [
          const DropdownMenuItem(value: '', child: Text('No icon')),
          for (final s in PlantSymbol.values)
            DropdownMenuItem(
              value: s.name,
              child: Text('${symbolLabels[s]} ${s.name}'),
            ),
        ],
        onChanged: (s) =>
            onSymbol(s == '' ? null : PlantSymbol.values.byName(s!)),
      ),
    ],
  );
}
