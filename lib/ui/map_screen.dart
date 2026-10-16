import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';
import 'coordinate_preview.dart';
import 'plant_symbols.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focus});
  final Coordinates? focus;
  @override
  ConsumerState<MapScreen> createState() => _MapState();
}

class _MapState extends ConsumerState<MapScreen> {
  GoogleMapController? controller;
  Coordinates? selected;
  String? locationMessage;
  bool locating = false;
  @override
  void initState() {
    super.initState();
    if (widget.focus != null) {
      locationMessage =
          'Plant saved locally. Tap its marker to open Plant Detail.';
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null && widget.focus != oldWidget.focus) {
      selected = null;
      locationMessage =
          'Plant saved locally. Tap its marker to open Plant Detail.';
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(widget.focus!.latitude, widget.focus!.longitude),
          19,
        ),
      );
    }
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted) return;
      setState(() {
        selected = fix.coordinates;
        locationMessage =
            'GPS accuracy ±${fix.accuracyMeters.round()} m. Adjust coordinates if needed.';
      });
      await controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(fix.coordinates.latitude, fix.coordinates.longitude),
          19,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => locationMessage = '$error');
    } finally {
      if (mounted) setState(() => locating = false);
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
    // Lock and unmount all screens before terminating/clearing the native cache.
    final orchard = ref.read(orchardRepositoryProvider);
    final auth = ref.read(authRepositoryProvider);
    ref.read(sessionLockedProvider.notifier).state = true;
    try {
      await orchard.clearDeviceCache();
      await auth.signOut();
    } catch (_) {
      // Keep the session locked; another account must never see a stale cache.
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = ref.watch(placeProvider);
    final plants = ref.watch(plantsProvider);
    final taxonomy = ref.watch(taxonomyProvider);
    final markerSymbols = ref.watch(trialModeProvider)
        ? null
        : ref.watch(markerSymbolsProvider).valueOrNull;
    PlantSymbol symbolFor(String id) =>
        taxonomy.taxa.where((t) => t.id == id).firstOrNull?.symbol ??
        PlantSymbol.tree;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(place.valueOrNull?.name ?? 'OrchardAtlas'),
          actions: [
            IconButton(
              onPressed: signOut,
              tooltip: 'Sign out and clear device cache',
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Map'),
              Tab(text: 'Plants'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: place.hasValue
              ? () => context.push('/plants/new', extra: selected)
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Add Plant'),
        ),
        body: plants.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(
            e,
            retry: () {
              ref.invalidate(placeProvider);
              ref.invalidate(plantsProvider);
            },
          ),
          data: (snapshot) {
            final items = snapshot.value;
            final center =
                selected ??
                widget.focus ??
                (items.isNotEmpty ? items.first.location : null);
            return Column(
              children: [
                SyncStatus(snapshot),
                if (locationMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(locationMessage!),
                  ),
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
                    TextButton(
                      onPressed: () =>
                          ref.read(locationRepositoryProvider).openSettings(),
                      child: const Text('Settings'),
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      if (ref.watch(trialModeProvider))
                        CoordinatePreview(
                          plants: items,
                          selected: selected,
                          focus: widget.focus,
                          onSelect: (coordinates) => setState(() {
                            selected = coordinates;
                            locationMessage = 'Coordinate selected for Add Plant. Adjust coordinates on the plant form if needed.';
                          }),
                          onOpen: (id) => context.push('/plants/$id'),
                        )
                      else
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: center == null
                                ? const LatLng(0, 0)
                                : LatLng(center.latitude, center.longitude),
                            zoom: center == null ? 2 : 18,
                          ),
                          onMapCreated: (map) {
                            controller = map;
                            // GPS or save focus can arrive while the native view
                            // is still initializing; initialCameraPosition is not
                            // reapplied to an existing native map.
                            final latest = selected ?? widget.focus;
                            if (latest != null) {
                              map.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(latest.latitude, latest.longitude),
                                  19,
                                ),
                              );
                            }
                          },
                          onTap: (p) => setState(() {
                            selected = Coordinates(p.latitude, p.longitude);
                            locationMessage =
                                'Map position selected for Add Plant.';
                          }),
                          markers: {
                            for (final p in items)
                              Marker(
                                markerId: MarkerId(p.id),
                                position: LatLng(
                                  p.location.latitude,
                                  p.location.longitude,
                                ),
                                icon:
                                    markerSymbols?[symbolFor(p.taxonId)] ??
                                    BitmapDescriptor.defaultMarker,
                                infoWindow: InfoWindow(title: p.name),
                                onTap: () => context.push('/plants/${p.id}'),
                              ),
                            if (selected != null)
                              Marker(
                                markerId: const MarkerId('selected-position'),
                                position: LatLng(
                                  selected!.latitude,
                                  selected!.longitude,
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueAzure,
                                ),
                                infoWindow: const InfoWindow(
                                  title: 'Selected add location',
                                ),
                              ),
                          },
                        ),
                      items.isEmpty
                          ? const Center(
                              child: Text(
                                'No cached plants yet. Add your first plant.',
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 96),
                              itemCount: items.length,
                              itemBuilder: (context, i) => ListTile(
                                leading: Text(
                                  symbolLabels[symbolFor(items[i].taxonId)]!,
                                  style: const TextStyle(fontSize: 28),
                                ),
                                title: Text(items[i].name),
                                subtitle: Text(
                                  '${items[i].location.latitude.toStringAsFixed(6)}, ${items[i].location.longitude.toStringAsFixed(6)}',
                                ),
                                onTap: () =>
                                    context.push('/plants/${items[i].id}'),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
