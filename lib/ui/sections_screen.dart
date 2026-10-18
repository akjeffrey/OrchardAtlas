import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';
import 'common.dart';
import 'orchard_map.dart';
import 'location_search.dart';
import 'tasks_screen.dart';
import 'section_style.dart';
import '../domain/work.dart';
import 'delete_actions.dart';

String sectionPath(OrchardSection section, List<OrchardSection> sections) {
  final names = <String>[section.name], seen = <String>{section.id};
  var parent = section.parentId;
  while (parent != null && seen.add(parent)) {
    final found = sections.where((s) => s.id == parent).firstOrNull;
    if (found == null) break;
    names.insert(0, found.name);
    parent = found.parentId;
  }
  return names.join(' › ');
}

class SectionPicker extends ConsumerWidget {
  const SectionPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Area / row',
    this.empty = 'Unassigned',
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label, empty;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionsProvider);
    return sections.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Areas unavailable: $e'),
      data: (snapshot) => DropdownButtonFormField<String>(
        key: ValueKey('$label-$value-${snapshot.value.length}'),
        initialValue: snapshot.value.any((s) => s.id == value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: '', child: Text(empty)),
          for (final s in snapshot.value)
            DropdownMenuItem(
              value: s.id,
              child: Text(
                sectionPath(s, snapshot.value),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) => onChanged(id == '' ? null : id),
      ),
    );
  }
}

class SectionsScreen extends ConsumerWidget {
  const SectionsScreen({super.key, this.initialCamera});
  final CameraPosition? initialCamera;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Areas & Rows'),
      leading: IconButton(
        tooltip: 'Back to map',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/'),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => context.push('/sections/new', extra: initialCamera),
      icon: const Icon(Icons.add),
      label: const Text('Add area or row'),
    ),
    body: ref
        .watch(sectionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorPanel(e, retry: () => ref.invalidate(sectionsProvider)),
          data: (snapshot) => Column(
            children: [
              SyncStatus(snapshot),
              Expanded(
                child: snapshot.value.isEmpty
                    ? const Center(
                        child: Text(
                          'Add an Area or Row.\nThen assign plants and seasonal varieties.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          SizedBox(
                            height: 240,
                            child: OrchardMap(
                              sections: snapshot.value,
                              onSection: (id) => context.push('/sections/$id'),
                            ),
                          ),
                          for (final s in snapshot.value)
                            ListTile(
                              leading: Icon(
                                s.kind == SectionKind.row
                                    ? Icons.timeline
                                    : Icons.crop_square,
                              ),
                              title: Text(sectionPath(s, snapshot.value)),
                              subtitle: Text(s.kind.name),
                              onTap: () => context.push('/sections/${s.id}'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
  );
}

class SectionFormScreen extends ConsumerStatefulWidget {
  const SectionFormScreen({
    super.key,
    this.sectionId,
    this.parentId,
    this.initialCamera,
  });
  final CameraPosition? initialCamera;
  final String? sectionId, parentId;
  @override
  ConsumerState<SectionFormScreen> createState() => _SectionFormState();
}

class _SectionFormState extends ConsumerState<SectionFormScreen> {
  final name = TextEditingController(), notes = TextEditingController();
  final points = <Coordinates>[];
  SectionKind kind = SectionKind.area;
  int color = 0xff4caf50;
  PlantSymbol? symbol;
  String? customIconId;
  String? parentId, error;
  Coordinates? center;
  double span = 0.0005;
  bool initialized = false, busy = false;
  GoogleMapController? map;
  @override
  void initState() {
    super.initState();
    parentId = widget.parentId;
    final initial = widget.initialCamera;
    if (initial != null) {
      center = Coordinates(initial.target.latitude, initial.target.longitude);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.sectionId == null && widget.initialCamera == null) {
        locate();
      }
    });
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted) return;
      setState(() => center = fix.coordinates);
      map?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(center!.latitude, center!.longitude),
          19,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'GPS unavailable. Add coordinates manually to start drawing.',
        );
      }
    }
  }

  Future<void> point([int? index]) async {
    var lat = index == null ? '' : points[index].latitude.toString(),
        lon = index == null ? '' : points[index].longitude.toString();
    String? message;
    final result = await showDialog<Coordinates>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            index == null ? 'Add vertex' : 'Edit vertex ${index + 1}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (v) => lat = v,
              ),
              TextFormField(
                initialValue: lon,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (v) => lon = v,
              ),
              if (message != null) Text(message!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    Coordinates(double.parse(lat), double.parse(lon)),
                  );
                } catch (_) {
                  update(() => message = 'Enter valid latitude and longitude');
                }
              },
              child: const Text('Use vertex'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          points.add(result);
        } else {
          points[index] = result;
        }
        center = result;
      });
      if (mounted) {
        map?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(result.latitude, result.longitude),
            19,
          ),
        );
      }
    }
  }

  Future<void> save(List<OrchardSection> sections) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final old = sections.where((s) => s.id == widget.sectionId).firstOrNull;
      final section = OrchardSection(
        id: old?.id ?? const Uuid().v4(),
        propertyId: place.id,
        name: name.text,
        kind: kind,
        color: color,
        symbol: symbol,
        customIconId: customIconId,
        parentId: parentId,
        notes: notes.text,
        vertices: points,
        createdAt: old?.createdAt ?? DateTime.now().toUtc(),
      );
      validateSectionParent(section, sections);
      ref.read(orchardRepositoryProvider).saveSection(section);
      context.go('/sections/${section.id}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> backToMap() async {
    if (busy) return;
    if (points.isNotEmpty || name.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave area / row editor?'),
          content: const Text('Unsaved changes will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Back to map'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sectionsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to map',
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : backToMap,
        ),
        actions: [
          IconButton(
            tooltip: 'Search map location',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showLocationSearch(context);
              if (result == null || !mounted) return;
              setState(() => center = result.coordinates);
              map?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(center!.latitude, center!.longitude),
                  19,
                ),
              );
            },
          ),
        ],
        title: Text(
          widget.sectionId == null ? 'Draw area or row' : 'Edit area or row',
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorPanel(e),
        data: (snapshot) {
          final old = snapshot.value
              .where((s) => s.id == widget.sectionId)
              .firstOrNull;
          if (widget.sectionId != null && old == null) {
            return const ErrorPanel('Section unavailable');
          }
          if (!initialized) {
            if (old != null) {
              name.text = old.name;
              notes.text = old.notes;
              kind = old.kind;
              color = old.color;
              symbol = old.symbol;
              customIconId = old.customIconId;
              parentId = old.parentId;
              points.addAll(old.vertices);
              center = points.first;
            } else {
              center ??= snapshot.value
                  .where((s) => s.id == parentId)
                  .firstOrNull
                  ?.vertices
                  .first;
            }
            initialized = true;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: name,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Area / row name'),
              ),
              DropdownButtonFormField<SectionKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Shape type'),
                items: [
                  for (final k in SectionKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Text(
                        k == SectionKind.row
                            ? 'Row (line)'
                            : '${k.name} (area)',
                      ),
                    ),
                ],
                onChanged: old != null
                    ? null
                    : (k) => setState(() => kind = k!),
              ),
              DropdownButtonFormField<String>(
                initialValue: parentId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Inside Area'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Whole property'),
                  ),
                  for (final s in snapshot.value.where(
                    (s) => s.kind != SectionKind.row && s.id != old?.id,
                  ))
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        sectionPath(s, snapshot.value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: old != null
                    ? null
                    : (id) => setState(() => parentId = id == '' ? null : id),
              ),
              SectionStyleFields(
                color: color,
                symbol: symbol,
                customIconId: customIconId,
                onCustomIcon: (v) => setState(() => customIconId = v),
                onColor: (v) => setState(() => color = v),
                onSymbol: (v) => setState(() => symbol = v),
              ),
              const Text(
                'Tap to add vertices in order. Areas close automatically. Edit a numbered vertex below to reposition it.',
              ),
              SizedBox(
                height: 300,
                child: OrchardMap(
                  sections: snapshot.value
                      .where((s) => s.id != old?.id)
                      .toList(),
                  initialCamera: widget.initialCamera,
                  draft: List.of(points),
                  draftKind: kind,
                  center: center,
                  span: span,
                  onMapCreated: (c) {
                    map = c;
                    if (widget.initialCamera != null) {
                      c.animateCamera(
                        CameraUpdate.newCameraPosition(widget.initialCamera!),
                      );
                    } else if (center != null) {
                      c.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(center!.latitude, center!.longitude),
                          19,
                        ),
                      );
                    }
                  },
                  onTap: busy
                      ? null
                      : (p) => setState(() {
                          if (points.length < 40) points.add(p);
                        }),
                  onMoveVertex: busy
                      ? null
                      : (i, p) => setState(() => points[i] = p),
                ),
              ),
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : locate,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Center on GPS'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      span = (span / 2).clamp(0.00001, 1);
                      map?.animateCamera(CameraUpdate.zoomIn());
                    }),
                    child: const Text('Zoom in'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      span = (span * 2).clamp(0.00001, 1);
                      map?.animateCamera(CameraUpdate.zoomOut());
                    }),
                    child: const Text('Zoom out'),
                  ),
                  TextButton(
                    onPressed: busy || points.isEmpty
                        ? null
                        : () => setState(() => points.removeLast()),
                    child: const Text('Undo vertex'),
                  ),
                  TextButton(
                    onPressed: busy || points.length >= 40
                        ? null
                        : () => point(),
                    child: const Text('Enter coordinate'),
                  ),
                ],
              ),
              for (var i = 0; i < points.length; i++)
                ListTile(
                  title: Text(
                    '${i + 1}${kind == SectionKind.row && i == 0
                        ? ' (Start)'
                        : kind == SectionKind.row && i == points.length - 1
                        ? ' (Finish)'
                        : ''}: ${points[i].latitude.toStringAsFixed(7)}, ${points[i].longitude.toStringAsFixed(7)}',
                  ),
                  onTap: () => point(i),
                  trailing: IconButton(
                    tooltip: 'Remove vertex ${i + 1}',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => points.removeAt(i)),
                  ),
                ),
              TextField(
                controller: notes,
                maxLines: 3,
                maxLength: 10000,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (error != null) Text(error!),
              FilledButton(
                onPressed: busy ? null : () => save(snapshot.value),
                child: Text(busy ? 'Saving…' : 'Save area / row'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SectionDetailScreen extends ConsumerWidget {
  const SectionDetailScreen(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to map',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/'),
      ),
      title: const Text('Area / row detail'),
      actions: [
        IconButton(
          tooltip: 'All areas',
          onPressed: () => context.go('/layout'),
          icon: const Icon(Icons.list),
        ),
      ],
    ),
    body: ref
        .watch(sectionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(e),
          data: (snapshot) {
            final s = snapshot.value.where((s) => s.id == id).firstOrNull;
            if (s == null) return const ErrorPanel('Section unavailable');
            final descendants = sectionDescendants(id, snapshot.value);
            final plants = (ref.watch(plantsProvider).valueOrNull?.value ?? [])
                .where((p) => descendants.contains(p.sectionId))
                .toList();
            if (s.kind == SectionKind.row) {
              plants.sort(
                (a, b) => rowPosition(a, s).compareTo(rowPosition(b, s)),
              );
            }
            final crops = ref.watch(cropsProvider);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  sectionPath(s, snapshot.value),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(s.kind.name),
                if (s.kind == SectionKind.row)
                  Text(
                    'Start: ${s.vertices.first.latitude}, ${s.vertices.first.longitude} → Finish: ${s.vertices.last.latitude}, ${s.vertices.last.longitude}',
                  ),
                Text(s.notes),
                SyncStatus(snapshot),
                SizedBox(
                  height: 220,
                  child: OrchardMap(
                    sections: snapshot.value
                        .where((x) => descendants.contains(x.id))
                        .toList(),
                    plants: plants,
                    onSection: (sid) => context.push('/sections/$sid'),
                    onPlant: (pid) => context.push('/plants/$pid'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/sections/$id/edit'),
                      child: const Text('Edit shape'),
                    ),
                    TextButton(
                      onPressed: () =>
                          deleteSectionWithConfirmation(context, ref, s),
                      child: const Text('Delete permanently'),
                    ),
                    if (s.kind != SectionKind.row)
                      TextButton(
                        onPressed: () =>
                            context.push('/sections/new', extra: id),
                        child: const Text('Add child area / row'),
                      ),
                    TextButton(
                      onPressed: () => context.push('/plants/new', extra: s),
                      child: const Text('Add plant here'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/crops/new', extra: s),
                      child: const Text('Add seasonal planting'),
                    ),
                    TextButton(
                      onPressed: () => context.push(
                        '/tasks/new',
                        extra: TaskTarget(sectionId: id),
                      ),
                      child: const Text('Add task for this area'),
                    ),
                  ],
                ),
                for (final child in snapshot.value.where(
                  (x) => x.parentId == id,
                ))
                  ListTile(
                    leading: const Icon(Icons.timeline),
                    title: Text(child.name),
                    subtitle: Text(child.kind.name),
                    onTap: () => context.push('/sections/${child.id}'),
                  ),
                Text(
                  'Plants (${plants.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final p in plants)
                  ListTile(
                    title: Text(p.name),
                    trailing: s.kind != SectionKind.row
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Move plant earlier',
                                icon: const Icon(Icons.arrow_upward),
                                onPressed: plants.indexOf(p) == 0
                                    ? null
                                    : () {
                                        final ids = plants
                                            .map((p) => p.id)
                                            .toList();
                                        final i = ids.indexOf(p.id);
                                        ids.removeAt(i);
                                        ids.insert(i - 1, p.id);
                                        ref
                                            .read(orchardRepositoryProvider)
                                            .saveRowOrder(
                                              s.propertyId,
                                              s.id,
                                              ids,
                                            );
                                      },
                              ),
                              IconButton(
                                tooltip: 'Move plant later',
                                icon: const Icon(Icons.arrow_downward),
                                onPressed:
                                    plants.indexOf(p) == plants.length - 1
                                    ? null
                                    : () {
                                        final ids = plants
                                            .map((p) => p.id)
                                            .toList();
                                        final i = ids.indexOf(p.id);
                                        ids.removeAt(i);
                                        ids.insert(i + 1, p.id);
                                        ref
                                            .read(orchardRepositoryProvider)
                                            .saveRowOrder(
                                              s.propertyId,
                                              s.id,
                                              ids,
                                            );
                                      },
                              ),
                            ],
                          ),
                    subtitle: Text(
                      '${ref.watch(taxonomyProvider).taxa.where((t) => t.id == p.taxonId).firstOrNull?.name ?? 'Unknown classification'} · ${p.status.name}',
                    ),
                    onTap: () => context.push('/plants/${p.id}'),
                  ),
                Text(
                  'Seasonal plantings & history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                crops.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Crops unavailable: $e'),
                  data: (data) {
                    final entries =
                        data.value
                            .where((c) => descendants.contains(c.sectionId))
                            .toList()
                          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    return Column(
                      children: [
                        if (entries.isEmpty)
                          const Text('No seasonal plantings yet.'),
                        for (final c in entries)
                          ListTile(
                            title: Text('${c.label} · ${c.season}'),
                            subtitle: Text(
                              '${c.status.name} · ${c.plantedOn ?? 'Planting date unknown'}',
                            ),
                            onTap: () => context.push('/crops/${c.id}'),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
  );
}
