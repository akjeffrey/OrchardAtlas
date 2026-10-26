import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/landscape.dart';
import '../domain/models.dart';
import '../domain/orchards.dart';
import 'section_style.dart';
import 'common.dart';
import 'location_search.dart';
import 'orchard_map.dart';
import 'plant_filters.dart';
import 'plants_list.dart';
import 'plantings_screen.dart';
import 'version_history_screen.dart';
import 'sections_screen.dart';
import 'tasks_screen.dart';
import 'orchard_picker.dart';
import 'foraging_screen.dart';
import '../application/workspaces.dart';
import '../domain/workspaces.dart';

class OrchardHome extends ConsumerWidget {
  const OrchardHome({super.key, this.focus, this.focusPlantId});
  final Coordinates? focus;
  final String? focusPlantId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Explicit plant navigation always reaches the orchard map, then Back returns.
    if (focus != null || focusPlantId != null) {
      return _OrchardHome(focus: focus, focusPlantId: focusPlantId);
    }
    return ref
        .watch(workspaceModeProvider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            body: ErrorPanel(
              e,
              retry: () => ref.invalidate(workspaceModeProvider),
            ),
          ),
          data: (mode) => mode == WorkspaceMode.foraging
              ? ref
                    .watch(placeProvider)
                    .when(
                      skipLoadingOnRefresh: false,
                      data: (place) => ForagingScreen(
                        key: ValueKey('foraging-${place.id}'),
                        homeMode: true,
                      ),
                      loading: () => const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Scaffold(
                        body: ErrorPanel(
                          e,
                          retry: () => ref.invalidate(placeProvider),
                        ),
                      ),
                    )
              : const _OrchardHome(),
        );
  }
}

class _OrchardHome extends ConsumerWidget {
  const _OrchardHome({this.focus, this.focusPlantId});
  final String? focusPlantId;
  final Coordinates? focus;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(placeProvider)
      .when(
        skipLoadingOnRefresh: false,
        data: (place) => ref
            .watch(defaultMapViewProvider)
            .when(
              skipLoadingOnRefresh: false,
              data: (view) => MapScreen(
                key: ValueKey(place.id),
                focus: focus,
                focusPlantId: focusPlantId,
                initialView: view,
              ),
              error: (_, _) => MapScreen(
                key: ValueKey(place.id),
                focus: focus,
                focusPlantId: focusPlantId,
              ),
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            ),
        error: (e, _) => Scaffold(
          body: ErrorPanel(e, retry: () => ref.invalidate(placeProvider)),
        ),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
}

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focus, this.initialView, this.focusPlantId});
  final String? focusPlantId;
  final OrchardMapView? initialView;
  final Coordinates? focus;
  @override
  ConsumerState<MapScreen> createState() => _MapState();
}

class _MapState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  GoogleMapController? controller;
  Coordinates? selected, cameraCenter;
  CameraPosition? cameraPosition;
  bool beforeDrawingFullScreen = false;
  String? locationMessage;
  bool locating = false, fullScreen = false, saving = false;
  SectionKind? drawing;
  final draft = <Coordinates>[];

  @override
  void initState() {
    super.initState();
    final view = widget.initialView;
    if (view != null) {
      fullScreen = view.fullScreen;
      if (widget.focus == null && widget.focusPlantId == null) {
        cameraCenter = view.center;
        cameraPosition = CameraPosition(
          target: LatLng(view.center.latitude, view.center.longitude),
          zoom: view.zoom,
          bearing: view.bearing,
          tilt: view.tilt,
        );
      }
    }
    tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (tabs.index != 0) controller = null;
        if (mounted) setState(() {});
      });
    if (widget.focus != null) {
      locationMessage = widget.focusPlantId == null
          ? 'Plant saved locally. Tap its marker to open Plant Detail.'
          : 'Showing saved plant location. Use Back to return to the previous page.';
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null && widget.focus != oldWidget.focus) {
      selected = null;
      locationMessage = widget.focusPlantId == null
          ? 'Plant saved locally. Tap its marker to open Plant Detail.'
          : 'Showing saved plant location. Use Back to return to the previous page.';
      moveTo(widget.focus!);
    }
  }

  void moveTo(Coordinates point) {
    cameraCenter = point;
    cameraPosition = CameraPosition(
      target: LatLng(point.latitude, point.longitude),
      zoom: 19,
      bearing: cameraPosition?.bearing ?? 0,
      tilt: cameraPosition?.tilt ?? 0,
    );
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(point.latitude, point.longitude), 19),
    );
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted) return;
      setState(() {
        if (drawing == null) selected = fix.coordinates;
        locationMessage = 'GPS accuracy ±${fix.accuracyMeters.round()} m.';
        moveTo(fix.coordinates);
      });
    } catch (error) {
      if (mounted) setState(() => locationMessage = '$error');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> search() async {
    final result = await showLocationSearch(context);
    if (!mounted || result == null) return;
    setState(() {
      if (drawing == null) selected = result.coordinates;
      locationMessage = result.label;
      moveTo(result.coordinates);
    });
  }

  void startDrawing(SectionKind kind) => setState(() {
    cameraCenter ??= selected ?? widget.focus;
    drawing = kind;
    beforeDrawingFullScreen = fullScreen;
    fullScreen = true;
    selected = null;
    draft.clear();
    locationMessage = null;
  });

  Future<bool> discardDrawing() async {
    if (draft.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this drawing?'),
          content: const Text('The unsaved row or area will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep drawing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return false;
    }
    if (mounted) {
      setState(() {
        drawing = null;
        fullScreen = beforeDrawingFullScreen;
        draft.clear();
      });
    }
    return true;
  }

  Future<void> saveDrawing(List<OrchardSection> sections) async {
    if (saving || drawing == null) return;
    try {
      validateGeometry(drawing!, draft);
    } catch (e) {
      setState(() => locationMessage = '$e');
      return;
    }
    var name = '', parent = '';
    var color = 0xff4caf50;
    PlantSymbol? symbol;
    String? customIconId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save ${drawing!.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Area / row name'),
                onChanged: (v) => name = v,
              ),
              SectionStyleFields(
                color: color,
                symbol: symbol,
                customIconId: customIconId,
                onCustomIcon: (v) => customIconId = v,
                onColor: (v) => color = v,
                onSymbol: (v) => symbol = v,
              ),
              DropdownButtonFormField<String>(
                initialValue: '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Inside area / bed',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Whole property'),
                  ),
                  for (final s in sections.where(
                    (s) => s.kind != SectionKind.row,
                  ))
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        sectionPath(s, sections),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => parent = v ?? '',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep drawing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save shape'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => saving = true);
    try {
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final section = OrchardSection(
        id: const Uuid().v4(),
        propertyId: place.id,
        name: name,
        kind: drawing!,
        color: color,
        symbol: symbol,
        customIconId: customIconId,
        vertices: List.of(draft),
        parentId: parent.isEmpty ? null : parent,
        createdAt: DateTime.now().toUtc(),
      );
      validateSectionParent(section, sections);
      ref.read(orchardRepositoryProvider).saveSection(section);
      setState(() {
        drawing = null;
        fullScreen = beforeDrawingFullScreen;
        draft.clear();
        locationMessage = '${section.name} saved locally.';
      });
    } catch (e) {
      if (mounted) setState(() => locationMessage = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> switchOrchard() async {
    if (drawing != null && !await discardDrawing()) return;
    if (!mounted) return;
    await switchWorkspace(context, ref);
  }

  Future<void> mapSettings() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map settings'),
        content: const Text(
          'Save this map location, zoom and display mode as the default for this orchard. It will reopen here next time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set current view as default'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final place = await ref.read(placeProvider.future);
      final position = cameraPosition;
      final center = cameraCenter ?? selected ?? widget.focus;
      if (center == null || (position != null && position.zoom <= 2)) {
        throw StateError('Move or locate the map at your orchard first');
      }
      await ref
          .read(mapViewRepositoryProvider)
          .save(
            place.ownerId,
            place.id,
            OrchardMapView(
              center: center,
              zoom: position?.zoom ?? 19,
              bearing: position?.bearing ?? 0,
              tilt: position?.tilt ?? 0,
              fullScreen: fullScreen,
            ),
          );
      // Keep this screen/camera mounted; startup reloads the saved preference.
      if (mounted) {
        setState(
          () => locationMessage = 'Default map view saved for ${place.name}.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => locationMessage = '$e');
    }
  }

  Future<void> signOut() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out and clear cached records?'),
        content: const Text(
          'Pending offline changes can be lost. Wait until records sync before signing out. You will need to restart the app afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final orchard = ref.read(orchardRepositoryProvider);
    final auth = ref.read(authRepositoryProvider);
    ref.read(sessionLockedProvider.notifier).state = true;
    try {
      try {
        await ref.read(reminderSchedulerProvider).clear();
      } catch (_) {
        /* Platforms without notification support have no pending reminders. */
      }
      await orchard.clearDeviceCache();
      await auth.signOut();
    } catch (_) {
      /* Keep the session locked if cache clearing fails. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = ref.watch(placeProvider), plants = ref.watch(plantsProvider);
    final taxonomy = ref.watch(taxonomyProvider);
    final sectionData = ref.watch(sectionsProvider);
    final sections = sectionData.asData?.value.value ?? <OrchardSection>[];
    final isMap = tabs.index == 0;
    return PopScope(
      canPop: !fullScreen && drawing == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (drawing != null) {
          await discardDrawing();
          return;
        }
        if (mounted) setState(() => fullScreen = false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: drawing != null || fullScreen
              ? IconButton(
                  tooltip: 'Back to map',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: saving
                      ? null
                      : () async {
                          if (drawing != null) {
                            await discardDrawing();
                          } else {
                            setState(() => fullScreen = false);
                          }
                        },
                )
              : IconButton(
                  tooltip: 'Switch mode or orchard',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: switchOrchard,
                ),
          title: Text(
            fullScreen
                ? '${place.valueOrNull?.name ?? 'Orchard'} map'
                : place.valueOrNull?.name ?? 'OrchardAtlas',
          ),
          actions: [
            if (isMap)
              IconButton(
                tooltip: 'Search map location',
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            if (isMap)
              IconButton(
                tooltip: fullScreen ? 'Data mode' : 'Full screen map',
                onPressed: () => setState(() => fullScreen = !fullScreen),
                icon: Icon(
                  fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            if (drawing == null)
              PopupMenuButton<String>(
                tooltip: 'Orchard options',
                onSelected: (v) {
                  if (v == 'layout') {
                    context.push('/layout', extra: cameraPosition);
                  }
                  if (v == 'orchards') switchOrchard();
                  if (v == 'settings') mapSettings();
                  if (v == 'app-settings') context.push('/settings');
                  if (v == 'archived') context.push('/archived');
                  if (v == 'classifications') context.push('/classifications');
                  if (v == 'plantings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlantingsScreen(),
                      ),
                    );
                  }
                  if (v == 'versions') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VersionHistoryScreen(),
                      ),
                    );
                  }
                  if (v == 'logout') signOut();
                  if (v == 'backup') context.push('/backup');
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'orchards',
                    child: Text('Select orchard'),
                  ),
                  PopupMenuItem(value: 'settings', child: Text('Map settings')),
                  PopupMenuItem(value: 'app-settings', child: Text('Settings')),
                  PopupMenuItem(
                    value: 'archived',
                    child: Text('Archived Plants'),
                  ),
                  PopupMenuItem(
                    value: 'classifications',
                    child: Text('Group / Type / Variety'),
                  ),
                  PopupMenuItem(value: 'layout', child: Text('Areas & Rows')),
                  if (ref.read(trialModeProvider))
                    PopupMenuItem(
                      value: 'backup',
                      child: Text('Backup & restore'),
                    ),
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Sign out and clear device cache'),
                  ),
                ],
              ),
          ],
          bottom: fullScreen || drawing != null
              ? null
              : TabBar(
                  controller: tabs,
                  tabs: const [
                    Tab(text: 'Map'),
                    Tab(text: 'Plants'),
                    Tab(text: 'Tasks'),
                  ],
                ),
        ),
        floatingActionButton: drawing != null
            ? null
            : FloatingActionButton.extended(
                onPressed: place.hasValue && !ref.watch(viewOnlyOrchardProvider)
                    ? () => tabs.index == 2
                          ? context.push('/tasks/new')
                          : context.push('/plants/new', extra: selected)
                    : null,
                icon: const Icon(Icons.add),
                label: Text(tabs.index == 2 ? 'Add task' : 'Add Plant'),
              ),
        body: tabs.index == 2
            ? const TasksPane()
            : plants.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorPanel(
                  e,
                  retry: () {
                    ref.invalidate(placeProvider);
                    ref.invalidate(plantsProvider);
                  },
                ),
                data: (snapshot) {
                  final items = ref
                      .watch(plantFilterProvider)
                      .apply(snapshot.value, taxonomy, sections: sections);
                  final initialCenter =
                      cameraCenter ??
                      selected ??
                      widget.focus ??
                      snapshot.value
                          .where(
                            (p) =>
                                p.id == widget.focusPlantId &&
                                p.status == ItemStatus.active,
                          )
                          .firstOrNull
                          ?.location ??
                      items.firstOrNull?.location ??
                      sections.firstOrNull?.vertices.first;
                  final initialCamera =
                      cameraPosition ??
                      (initialCenter == null
                          ? null
                          : CameraPosition(
                              target: LatLng(
                                initialCenter.latitude,
                                initialCenter.longitude,
                              ),
                              zoom: 19,
                            ));
                  return Column(
                    children: [
                      if (!fullScreen) ...[
                        SyncStatus(snapshot),
                        const PlantFilterBar(),
                        Text(
                          '${tabs.index == 1 ? 'Plant list' : '${items.length} of ${snapshot.value.length} plants'} · ${ref.watch(plantFilterProvider).status?.name ?? "all statuses"}',
                        ),
                      ],
                      if (locationMessage != null)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            locationMessage!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (sectionData.hasError)
                        const Text(
                          'Areas unavailable. Retry from Areas & Rows.',
                        ),
                      if (isMap) ...[
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: locating ? null : locate,
                              icon: const Icon(Icons.my_location),
                              label: Text(
                                locating ? 'Locating…' : 'Current GPS location',
                              ),
                            ),
                            if (drawing == null) ...[
                              TextButton.icon(
                                onPressed:
                                    sectionData.hasValue &&
                                        !ref.watch(viewOnlyOrchardProvider)
                                    ? () => startDrawing(SectionKind.row)
                                    : null,
                                icon: const Icon(Icons.timeline),
                                label: const Text('Add row'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    sectionData.hasValue &&
                                        !ref.watch(viewOnlyOrchardProvider)
                                    ? () => startDrawing(SectionKind.area)
                                    : null,
                                icon: const Icon(Icons.crop_square),
                                label: const Text('Add area'),
                              ),
                            ] else ...[
                              TextButton(
                                onPressed: draft.isEmpty || saving
                                    ? null
                                    : () => setState(() => draft.removeLast()),
                                child: const Text('Undo vertex'),
                              ),
                              TextButton(
                                onPressed: saving ? null : discardDrawing,
                                child: const Text('Cancel drawing'),
                              ),
                              FilledButton(
                                onPressed:
                                    saving ||
                                        draft.length <
                                            (drawing == SectionKind.row ? 2 : 3)
                                    ? null
                                    : () => saveDrawing(sections),
                                child: Text(
                                  saving ? 'Saving…' : 'Finish drawing',
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (drawing != null)
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              'Tap ${drawing == SectionKind.row ? "along the row" : "around the boundary"} · ${draft.length}/40 vertices · Drag pins to adjust',
                            ),
                          ),
                        Expanded(
                          key: const ValueKey('map-pane'),
                          child: OrchardMap(
                            sections:
                                ref.watch(plantFilterProvider).taxonId == null
                                ? sections
                                : sections.where((s) {
                                    final contained = sectionDescendants(
                                      s.id,
                                      sections,
                                    );
                                    return items.any(
                                      (p) =>
                                          p.status == ItemStatus.active &&
                                          contained.contains(p.sectionId),
                                    );
                                  }).toList(),
                            plants: [
                              ...items,
                              if (!items.any(
                                (p) => p.id == widget.focusPlantId,
                              ))
                                ...snapshot.value.where(
                                  (p) =>
                                      p.id == widget.focusPlantId &&
                                      p.status == ItemStatus.active,
                                ),
                            ],
                            focusPlantId: drawing == null
                                ? widget.focusPlantId
                                : null,
                            selected: selected,
                            draft: List.of(draft),
                            draftKind: drawing ?? SectionKind.row,
                            center: cameraCenter ?? selected ?? widget.focus,

                            initialCamera: initialCamera,
                            onCameraChanged: (position) =>
                                cameraPosition = position,
                            onMapCreated: (map) {
                              controller = map;
                              final latest = cameraPosition ?? initialCamera;
                              if (latest != null) {
                                cameraPosition = latest;
                                cameraCenter = Coordinates(
                                  latest.target.latitude,
                                  latest.target.longitude,
                                );
                                map.animateCamera(
                                  CameraUpdate.newCameraPosition(latest),
                                );
                              }
                            },
                            onCameraMove: (p) => cameraCenter = p,
                            onTap: saving
                                ? null
                                : (p) => setState(() {
                                    if (drawing != null) {
                                      if (draft.length < 40) {
                                        draft.add(p);
                                        locationMessage = null;
                                      } else {
                                        locationMessage = 'Maximum 40 vertices. Undo a point to replace it.';
                                      }
                                    } else {
                                      selected = p;
                                      locationMessage = 'Map position selected for Add Plant.';
                                    }
                                  }),
                            onMoveVertex: drawing == null || saving
                                ? null
                                : (i, p) => setState(() => draft[i] = p),
                            onPlant: drawing != null
                                ? null
                                : (id) => context.push('/plants/$id'),
                            onSection: drawing != null
                                ? null
                                : (id) => context.push('/sections/$id'),
                          ),
                        ),
                      ] else
                        Expanded(child: const PlantsList()),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
