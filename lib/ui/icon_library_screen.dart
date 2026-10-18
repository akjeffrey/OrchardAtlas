import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/map_icons.dart';
import 'common.dart';

class IconLibraryScreen extends ConsumerStatefulWidget {
  const IconLibraryScreen({super.key});
  @override
  ConsumerState<IconLibraryScreen> createState() => _IconLibraryState();
}

class _IconLibraryState extends ConsumerState<IconLibraryScreen> {
  bool busy = false;
  String? error;
  Future<void> importIcon() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final orchard = await ref.read(placeProvider.future);
      final bytes = await ref.read(iconImporterProvider).importPng();
      if (bytes == null || !mounted) return;
      var iconName = 'Custom icon';
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Name this icon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(bytes, width: 64, height: 64),
              TextFormField(
                initialValue: iconName,
                onChanged: (v) => iconName = v,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Icon name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (iconName.trim().isNotEmpty) {
                  Navigator.pop(context, iconName.trim());
                }
              },
              child: const Text('Save icon'),
            ),
          ],
        ),
      );
      if (name == null || !mounted) return;
      if ((await ref.read(placeProvider.future)).id != orchard.id) {
        throw StateError('Orchard changed; import again');
      }
      ref
          .read(orchardRepositoryProvider)
          .saveIcon(
            orchard.id,
            MapIcon(id: const Uuid().v4(), name: name, png: bytes),
          );
    } catch (e) {
      if (mounted) setState(() => error = 'Could not import icon: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteIcon(MapIcon icon) async {
    final orchard = await ref.read(placeProvider.future);
    final plants = await ref.read(plantsProvider.future);
    final sections = await ref.read(sectionsProvider.future);
    final taxonomy = ref.read(taxonomyProvider);
    final plantCount = plants.value
        .where((p) => taxonomy.iconFor(p.taxonId).customIconId == icon.id)
        .length;
    final sectionCount = sections.value
        .where((s) => s.customIconId == icon.id)
        .length;
    final optionCount = taxonomy.taxa
        .where((t) => t.customIconId == icon.id)
        .length;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${icon.name}?'),
        content: Text(
          'Used by $plantCount plants, $sectionCount Areas/Rows and $optionCount classification options. Affected items will show a question mark. Their data will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete icon'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if ((await ref.read(placeProvider.future)).id != orchard.id) {
      throw StateError('Orchard changed; try again');
    }
    ref.read(orchardRepositoryProvider).deleteIcon(orchard.id, icon.id);
  }

  Future<void> remove(MapIcon icon) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await deleteIcon(icon);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not delete icon: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Custom icons')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Choose an image from your device or Drive. Images are saved as small icons for this orchard and included in its backups.',
          ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(
          child: ref
              .watch(mapIconsProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorPanel(e),
                data: (icons) => icons.where((i) => !i.deleted).isEmpty
                    ? const Center(child: Text('No custom icons yet.'))
                    : ListView(
                        children: [
                          for (final icon in icons.where((i) => !i.deleted))
                            ListTile(
                              leading: Image.memory(
                                icon.png,
                                width: 32,
                                height: 32,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                              title: Text(icon.name),
                              trailing: IconButton(
                                tooltip: 'Delete ${icon.name}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: busy ? null : () => remove(icon),
                              ),
                            ),
                        ],
                      ),
              ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: busy ? null : importIcon,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(busy ? 'Importing…' : 'Import image'),
            ),
          ),
        ),
      ],
    ),
  );
}
