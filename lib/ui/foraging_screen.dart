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
import 'orchard_picker.dart';
import 'orchard_theme.dart';
import 'settings_screen.dart';
import 'location_search.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class ForagingScreen extends ConsumerStatefulWidget {
  const ForagingScreen({super.key, this.homeMode = false});
  final bool homeMode;
  @override
  ConsumerState<ForagingScreen> createState() => _ForagingHomeState();
}

class _ForagingHomeState extends ConsumerState<ForagingScreen> {
  bool map = true, fullScreen = false, locating = false;
  Coordinates? center;
  GoogleMapController? controller;
  String? message;
  Future<void> search() async {
    final result = await showLocationSearch(context);
    if (!mounted || result == null) return;
    move(result.coordinates);
  }

  void move(Coordinates point) {
    setState(() => center = point);
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(point.latitude, point.longitude), 18),
    );
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (mounted) {
        move(fix.coordinates);
        setState(
          () => message = 'GPS accuracy ±${fix.accuracyMeters.round()} m',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void open(ResourceRecord r) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ResourceDetail(r)),
  );
  @override
  Widget build(BuildContext context) {
    final orchard = ref.watch(placeProvider).valueOrNull;
    final resources = ref.watch(resourcesProvider);
    return PopScope(
      canPop: !fullScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => fullScreen = false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: widget.homeMode ? const WorkspaceSwitchButton() : null,
          title: const Text('Foraging'),
          actions: [
            if (map)
              IconButton(
                tooltip: 'Search map location',
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            if (map)
              IconButton(
                tooltip: fullScreen ? 'Data mode' : 'Full screen map',
                onPressed: () => setState(() => fullScreen = !fullScreen),
                icon: Icon(
                  fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            if (widget.homeMode)
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: ref.watch(canEditOrchardProvider)
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ResourceEditor(initialLocation: center),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add resource'),
              )
            : null,
        body: Column(
          children: [
            if (!fullScreen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Image.asset(OrchardBrand.logo, width: 40, height: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Foraging · ${orchard?.name ?? '…'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.map_outlined),
                          label: Text('Map'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.list),
                          label: Text('List'),
                        ),
                      ],
                      selected: {map},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => map = v.single),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: resources.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (all) {
                  if (!map) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Wild resources, seasonal observations and photos.',
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
                        for (final r in all)
                          Card(
                            child: ListTile(
                              leading: Icon(
                                r.inSeason(DateTime.now().month)
                                    ? Icons.eco
                                    : Icons.eco_outlined,
                                color: OrchardBrand.leaf,
                              ),
                              title: Text(r.name),
                              subtitle: Text(
                                '${r.startMonth}–${r.endMonth} · ${r.public ? 'Public' : 'Private'} · ${r.inSeason(DateTime.now().month) ? 'In season' : 'Out of season'}',
                              ),
                              onTap: () => open(r),
                            ),
                          ),
                        if (all.isEmpty)
                          const FormIntro(
                            title: 'Your next wild find',
                            subtitle: 'Add a resource to mark its location, season and observations.',
                            icon: Icons.eco_outlined,
                          ),
                      ],
                    );
                  }
                  final initial =
                      center ??
                      all.firstOrNull?.location ??
                      ref.watch(defaultMapViewProvider).valueOrNull?.center ??
                      Coordinates(0, 0);
                  return Column(
                    children: [
                      if (!fullScreen)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  all.isEmpty
                                      ? 'No resources yet · Add your first find'
                                      : '${all.length} foraging resource${all.length == 1 ? '' : 's'}',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Use current GPS location',
                                onPressed: locating ? null : locate,
                                icon: const Icon(Icons.my_location),
                              ),
                              if (ref.watch(sharingProvider) != null)
                                IconButton(
                                  tooltip: 'Browse public resources',
                                  icon: const Icon(Icons.public),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const PublicResourcesScreen(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (message != null && !fullScreen) Text(message!),
                      Expanded(
                        child: OrchardMap(
                          center: initial,
                          initialCamera: CameraPosition(
                            target: LatLng(initial.latitude, initial.longitude),
                            zoom: all.isEmpty && center == null
                                ? ref
                                          .watch(defaultMapViewProvider)
                                          .valueOrNull
                                          ?.zoom ??
                                      3
                                : 17,
                          ),
                          plants: [
                            for (final r in all)
                              ManagedPlant(
                                id: r.id,
                                propertyId: r.orchard,
                                name: r.name,
                                taxonId: r.taxonId,
                                location: r.location,
                                createdAt: r.createdAt,
                              ),
                          ],
                          onPlant: (id) =>
                              open(all.firstWhere((r) => r.id == id)),
                          onCameraMove: (p) => center = p,
                          onMapCreated: (c) => controller = c,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  const ResourceEditor({super.key, this.resource, this.initialLocation});
  final Coordinates? initialLocation;
  final ResourceRecord? resource;
  @override
  ConsumerState<ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends ConsumerState<ResourceEditor> {
  late final name = TextEditingController(text: widget.resource?.name),
      notes = TextEditingController(text: widget.resource?.notes);
  late String? taxon = widget.resource?.taxonId;
  late Coordinates? location =
      widget.resource?.location ?? widget.initialLocation;
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
    body: OrchardForm(
      title: 'Foraging resource',
      subtitle: 'Remember the location, harvest season and what you observe.',
      icon: Icons.eco_outlined,
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
