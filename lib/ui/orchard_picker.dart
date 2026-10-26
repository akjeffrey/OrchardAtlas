import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/workspaces.dart';
import '../domain/workspaces.dart';
import '../domain/filters.dart';

import 'package:go_router/go_router.dart';

import 'orchard_theme.dart';
import '../domain/models.dart';

class WorkspaceChoice {
  const WorkspaceChoice(this.place, this.mode);
  final Place place;
  final WorkspaceMode mode;
}

Future<WorkspaceChoice?> showWorkspacePicker(BuildContext context) =>
    showDialog<WorkspaceChoice>(
      context: context,
      builder: (_) => const _OrchardPicker(),
    );

Future<void> switchWorkspace(BuildContext context, WidgetRef ref) async {
  final next = await showWorkspacePicker(context);
  if (next == null || !context.mounted) return;
  final mode = ref.read(workspaceModeProvider.notifier);
  final selected = ref.read(selectedOrchardProvider.notifier);
  final taxa = ref.read(submittedTaxaProvider.notifier);
  final filter = ref.read(plantFilterProvider.notifier);
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await mode.select(next.mode);
    taxa.state = {};
    filter.state = const PlantFilter();
    selected.state = next.place;
    router.go('/');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not switch mode: $e')),
    );
  }
}

class WorkspaceSwitchButton extends ConsumerWidget {
  const WorkspaceSwitchButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Switch mode or orchard',
    icon: const Icon(Icons.swap_horiz),
    onPressed: () => switchWorkspace(context, ref),
  );
}

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
      await ref.read(placeProvider.future);
      final userId = ref.read(userProvider).value!.id;
      final directory = ref.read(orchardDirectoryProvider);
      final next = place ?? await directory.createPlace(userId, name.text);
      await directory.selectPlace(userId, next.id);
      if (mounted) {
        Navigator.pop(context, WorkspaceChoice(next, WorkspaceMode.orchard));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Image.asset(OrchardBrand.logo, width: 44, height: 44),
        const SizedBox(width: 12),
        const Expanded(child: Text('Mode & orchard')),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.eco_outlined,
                  color: OrchardBrand.leaf,
                ),
                title: const Text('Foraging'),
                subtitle: Text(
                  'Wild resources · ${ref.watch(placeProvider).valueOrNull?.name ?? 'Selected orchard'}',
                ),
                trailing:
                    ref.watch(workspaceModeProvider).valueOrNull ==
                        WorkspaceMode.foraging
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final place = await ref.read(placeProvider.future);
                          if (context.mounted) {
                            Navigator.pop(
                              context,
                              WorkspaceChoice(place, WorkspaceMode.foraging),
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your orchards',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
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
                          trailing: IconButton(
                            tooltip: 'Rename orchard',
                            icon: const Icon(Icons.edit),
                            onPressed:
                                busy ||
                                    place.ownerId !=
                                        ref.read(userProvider).valueOrNull?.id
                                ? null
                                : () async {
                                    var value = place.name;
                                    final yes = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Rename orchard'),
                                        content: TextFormField(
                                          initialValue: value,
                                          onChanged: (v) => value = v,
                                          decoration: const InputDecoration(
                                            labelText: 'Orchard name',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Save name'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes != true || !mounted) return;
                                    try {
                                      final directory = ref.read(
                                        orchardDirectoryProvider,
                                      );
                                      final renamed = await directory
                                          .renamePlace(
                                            place.ownerId,
                                            place.id,
                                            value,
                                          );
                                      await directory.selectPlace(
                                        place.ownerId,
                                        place.id,
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(
                                          context,
                                          WorkspaceChoice(
                                            renamed,
                                            WorkspaceMode.orchard,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) setState(() => error = '$e');
                                    }
                                  },
                          ),
                          leading: Icon(
                            place.id ==
                                        ref
                                            .watch(placeProvider)
                                            .valueOrNull
                                            ?.id &&
                                    ref
                                            .watch(workspaceModeProvider)
                                            .valueOrNull !=
                                        WorkspaceMode.foraging
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
