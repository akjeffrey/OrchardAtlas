import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/extensions.dart';
import '../domain/models.dart';
import 'classification_picker.dart';
import 'plant_location_picker.dart';
import 'photos_panel.dart';
import 'orchard_map.dart';

class ForagingScreen extends ConsumerWidget {
  const ForagingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Foraging resources')),
    floatingActionButton: ref.watch(canEditOrchardProvider)
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ResourceEditor()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add resource'),
          )
        : null,
    body: ref
        .watch(resourcesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (resources) => ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Private resources stay within this orchard. Public resources publish only the location, classification, name and season to signed-in users; observations and photos stay private.',
                ),
              ),
              if (ref.watch(sharingProvider) != null)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PublicResourcesScreen(),
                    ),
                  ),
                  child: const Text('Browse public resources'),
                ),
              for (final r in resources)
                ListTile(
                  leading: Icon(
                    r.inSeason(DateTime.now().month)
                        ? Icons.eco
                        : Icons.eco_outlined,
                  ),
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.startMonth}–${r.endMonth} · ${r.public ? 'Public' : 'Private'} · ${r.inSeason(DateTime.now().month) ? 'In season' : 'Out of season'}',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => ResourceDetail(r)),
                  ),
                ),
              if (resources.isEmpty)
                const ListTile(title: Text('No foraging resources yet.')),
            ],
          ),
        ),
  );
}

class ResourceDetail extends ConsumerWidget {
  const ResourceDetail(this.resource, {super.key});
  final ResourceRecord resource;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r =
        ref
            .watch(resourcesProvider)
            .valueOrNull
            ?.where((r) => r.id == resource.id)
            .firstOrNull ??
        resource;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          if (ref.watch(canEditOrchardProvider))
            IconButton(
              tooltip: 'Edit resource',
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ResourceEditor(resource: r),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 300,
            child: OrchardMap(
              plants: [
                ManagedPlant(
                  id: r.id,
                  propertyId: r.orchard,
                  name: r.name,
                  taxonId: r.taxonId,
                  location: r.location,
                  createdAt: r.createdAt,
                ),
              ],
              sections: const [],
              center: r.location,
              onPlant: (_) {},
              onTap: (_) {},
              onSection: (_) {},
              focusPlantId: r.id,
            ),
          ),
          Text(
            'Season: ${r.startMonth}–${r.endMonth} · ${r.public ? 'Public listing' : 'Private'}',
          ),
          Text(r.notes),
          PhotosPanel(r.id),
          Text('Observations', style: Theme.of(context).textTheme.titleLarge),
          ref
              .watch(recordsProvider(RecordKind.foraging))
              .when(
                data: (all) => Column(
                  children: [
                    for (final d in all.where((d) => d['parentId'] == r.id))
                      ListTile(
                        title: Text(d['observation'] as String),
                        subtitle: Text(d['date'] as String),
                      ),
                  ],
                ),
                error: (e, _) => Text('$e'),
                loading: () => const LinearProgressIndicator(),
              ),
          if (ref.watch(canEditOrchardProvider))
            TextButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Record observation'),
              onPressed: () async {
                final text = await showDialog<String>(
                  context: context,
                  builder: (_) => const _Observation(),
                );
                if (text == null) return;
                final id = const Uuid().v4();
                await ref.read(orchardRecordsProvider).putRecord(
                  r.orchard,
                  RecordKind.foraging,
                  id,
                  {
                    'parentId': r.id,
                    'observation': text,
                    'date': calendarDate(DateTime.now()),
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Observation extends StatefulWidget {
  const _Observation();
  @override
  State<_Observation> createState() => _ObservationState();
}

class _ObservationState extends State<_Observation> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Observation'),
    content: TextField(controller: text, maxLength: 10000, maxLines: 4),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (text.text.trim().isNotEmpty) {
            Navigator.pop(context, text.text.trim());
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class ResourceEditor extends ConsumerStatefulWidget {
  const ResourceEditor({super.key, this.resource});
  final ResourceRecord? resource;
  @override
  ConsumerState<ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends ConsumerState<ResourceEditor> {
  late final name = TextEditingController(text: widget.resource?.name),
      notes = TextEditingController(text: widget.resource?.notes);
  late String? taxon = widget.resource?.taxonId;
  late Coordinates? location = widget.resource?.location;
  late int start = widget.resource?.startMonth ?? 1,
      end = widget.resource?.endMonth ?? 12;
  late bool public = widget.resource?.public ?? false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.resource == null
            ? 'Add foraging resource'
            : 'Edit foraging resource',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Resource name'),
        ),
        ClassificationPicker(
          value: taxon,
          onChanged: (v) => setState(() => taxon = v),
        ),
        TextButton(
          onPressed: () async {
            try {
              final fix = await ref
                  .read(locationRepositoryProvider)
                  .currentPosition();
              if (mounted) setState(() => location = fix.coordinates);
            } catch (e) {
              if (mounted) setState(() => error = '$e');
            }
          },
          child: const Text('Use GPS location'),
        ),
        TextButton(
          onPressed: () async {
            final selected = await Navigator.push<Coordinates>(
              context,
              MaterialPageRoute(
                builder: (_) => PlantLocationPicker(
                  initialLocation:
                      location ??
                      ref.read(defaultMapViewProvider).valueOrNull?.center ??
                      Coordinates(0, 0),
                ),
              ),
            );
            if (selected != null && mounted) {
              setState(() => location = selected);
            }
          },
          child: const Text('Pick location on map'),
        ),
        if (location != null)
          Text('${location!.latitude}, ${location!.longitude}'),
        for (final isStart in [true, false])
          DropdownButtonFormField<int>(
            initialValue: isStart ? start : end,
            decoration: InputDecoration(
              labelText: isStart
                  ? 'Season begins (month)'
                  : 'Season ends (month)',
            ),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text('$m')),
            ],
            onChanged: (v) => setState(() {
              if (isStart) {
                start = v!;
              } else {
                end = v!;
              }
            }),
          ),
        SwitchListTile(
          title: const Text('Publish resource listing'),
          subtitle: const Text(
            'Requires connected mode. Exact location is included. Observations and photos remain private.',
          ),
          value: public,
          onChanged: (v) => setState(() => public = v),
        ),
        TextField(
          controller: notes,
          maxLength: 10000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Private notes'),
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    final orchard = await ref.read(placeProvider.future);
                    if (taxon == null || location == null) {
                      throw ArgumentError('Choose classification and location');
                    }
                    final r = ResourceRecord(
                      id: widget.resource?.id ?? const Uuid().v4(),
                      orchard: orchard.id,
                      name: name.text,
                      taxonId: taxon!,
                      location: location!,
                      createdAt: widget.resource?.createdAt ?? DateTime.now(),
                      startMonth: start,
                      endMonth: end,
                      public: public,
                      notes: notes.text,
                    );
                    await ref
                        .read(orchardRecordsProvider)
                        .putRecord(
                          orchard.id,
                          RecordKind.foraging,
                          r.id,
                          r.toMap(),
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('Save resource'),
        ),
      ],
    ),
  );
}

class PublicResourcesScreen extends ConsumerWidget {
  const PublicResourcesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Public foraging resources')),
    body: ref
        .watch(publicResourcesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (resources) => ListView(
            children: [
              const ListTile(
                title: Text(
                  'Up to 200 published resources. Private notes, observations and photos are excluded.',
                ),
              ),
              for (final r in resources)
                ListTile(
                  title: Text(r.name),
                  subtitle: Text('Season ${r.startMonth}–${r.endMonth}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(r.name)),
                        body: OrchardMap(
                          center: r.location,
                          focusPlantId: r.id,
                          plants: [
                            ManagedPlant(
                              id: r.id,
                              propertyId: r.orchard,
                              name: r.name,
                              taxonId: r.taxonId,
                              location: r.location,
                              createdAt: r.createdAt,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
  );
}
