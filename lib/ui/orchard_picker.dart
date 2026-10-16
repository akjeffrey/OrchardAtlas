import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';

Future<Place?> showOrchardPicker(BuildContext context) =>
    showDialog<Place>(context: context, builder: (_) => const _OrchardPicker());

class _OrchardPicker extends ConsumerStatefulWidget {
  const _OrchardPicker();
  @override
  ConsumerState<_OrchardPicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_OrchardPicker> {
  bool busy = false;
  String? error;
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> choose({Place? place}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final active = await ref.read(placeProvider.future);
      final directory = ref.read(orchardDirectoryProvider);
      final next =
          place ?? await directory.createPlace(active.ownerId, name.text);
      await directory.selectPlace(active.ownerId, next.id);
      if (mounted) Navigator.pop(context, next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select orchard'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ref
                .watch(orchardsProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Could not load orchards: $e'),
                  data: (places) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final place in places)
                        ListTile(
                          title: Text(place.name),
                          leading: Icon(
                            place.id == ref.watch(placeProvider).valueOrNull?.id
                                ? Icons.check_circle
                                : Icons.park,
                          ),
                          onTap: busy ? null : () => choose(place: place),
                        ),
                    ],
                  ),
                ),
            const Divider(),
            TextField(
              controller: name,
              maxLength: 500,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'New orchard name'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : () => choose(),
              icon: const Icon(Icons.add),
              label: const Text('Create orchard'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
