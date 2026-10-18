import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'icon_library_screen.dart';
import 'plant_symbols.dart';

class IconPreview extends ConsumerWidget {
  const IconPreview({
    super.key,
    this.symbol,
    this.customIconId,
    this.size = 24,
  });
  final PlantSymbol? symbol;
  final String? customIconId;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(mapIconsProvider).valueOrNull ?? [];
    final icon = icons.where((i) => i.id == customIconId).firstOrNull;
    return SizedBox(
      width: size,
      height: size,
      child: icon == null
          ? Center(
              child: Text(
                symbolLabels[symbol ?? PlantSymbol.tree]!,
                style: TextStyle(fontSize: size * .8),
              ),
            )
          : Image.memory(
              icon.png,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.image_not_supported_outlined, size: size),
            ),
    );
  }
}

class MapIconPicker extends ConsumerWidget {
  const MapIconPicker({
    super.key,
    this.symbol,
    this.customIconId,
    required this.onChanged,
    this.optional = false,
  });
  final PlantSymbol? symbol;
  final String? customIconId;
  final bool optional;
  final void Function(PlantSymbol?, String?) onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(mapIconsProvider).valueOrNull ?? [];
    final value = customIconId != null
        ? 'custom:$customIconId'
        : symbol == null && optional
        ? ''
        : 'builtin:${(symbol ?? PlantSymbol.tree).name}';
    Widget label(String text, PlantSymbol? builtIn, String? custom) => Row(
      children: [
        IconPreview(symbol: builtIn, customIconId: custom),
        const SizedBox(width: 8),
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('map-icon-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: optional ? 'Center icon (optional)' : 'Map icon',
          ),
          items: [
            if (optional)
              const DropdownMenuItem(value: '', child: Text('No icon')),
            for (final s in PlantSymbol.values)
              DropdownMenuItem(
                value: 'builtin:${s.name}',
                child: label(s.name, s, null),
              ),
            for (final icon in icons)
              DropdownMenuItem(
                value: 'custom:${icon.id}',
                child: label(icon.name, null, icon.id),
              ),
            if (customIconId != null && !icons.any((i) => i.id == customIconId))
              DropdownMenuItem(
                value: value,
                child: const Text('Saved icon (loading or unavailable)'),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            if (v == '') {
              onChanged(null, null);
            } else if (v.startsWith('custom:')) {
              onChanged(symbol ?? PlantSymbol.tree, v.substring(7));
            } else {
              onChanged(PlantSymbol.values.byName(v.substring(8)), null);
            }
          },
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const IconLibraryScreen()),
          ),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Import an icon'),
        ),
      ],
    );
  }
}

class TaxonOptionLabel extends ConsumerWidget {
  const TaxonOptionLabel({super.key, required this.taxon});
  final Taxon taxon;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(taxonomyProvider).iconFor(taxon.id);
    if (appearance.customIconId == null) {
      return Text(
        '${symbolLabels[appearance.symbol]} ${taxon.name}',
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        IconPreview(
          symbol: appearance.symbol,
          customIconId: appearance.customIconId,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(taxon.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
