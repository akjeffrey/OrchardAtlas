import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/providers.dart';
import '../domain/landscape.dart';
import '../domain/models.dart';
import '../domain/map_icons.dart';
import '../domain/work.dart';
import 'layout_canvas.dart';
import 'plant_symbols.dart';

/// The same satellite map is used for browsing and for drawing orchard geometry.
class OrchardMap extends ConsumerStatefulWidget {
  const OrchardMap({
    super.key,
    this.sections = const [],
    this.plants = const [],
    this.draft = const [],
    this.draftKind = SectionKind.row,
    this.center,
    this.selected,
    this.span,
    this.onTap,
    this.onPlant,
    this.onSection,
    this.onMapCreated,
    this.onCameraMove,
    this.onMoveVertex,
    this.initialCamera,
    this.onCameraChanged,
    this.onSelectedMoved,
  });
  final List<OrchardSection> sections;
  final List<ManagedPlant> plants;
  final List<Coordinates> draft;
  final SectionKind draftKind;
  final Coordinates? center, selected;
  final double? span;
  final ValueChanged<Coordinates>? onTap, onCameraMove;
  final ValueChanged<String>? onPlant, onSection;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final void Function(int, Coordinates)? onMoveVertex;
  final CameraPosition? initialCamera;
  final ValueChanged<CameraPosition>? onCameraChanged;
  final ValueChanged<Coordinates>? onSelectedMoved;

  @override
  ConsumerState<OrchardMap> createState() => _OrchardMapState();
}

class _OrchardMapState extends ConsumerState<OrchardMap> {
  String? selectedPlantId, selectedSectionId;
  GoogleMapController? controller;
  double? cameraZoom;

  bool visible(ManagedPlant plant) =>
      plant.status == ItemStatus.active && plant.sectionId == null;

  @override
  void didUpdateWidget(covariant OrchardMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPlant == null ||
        !widget.plants.any((p) => p.id == selectedPlantId && visible(p))) {
      selectedPlantId = null;
    }
    if (widget.onSection == null ||
        !widget.sections.any((s) => s.id == selectedSectionId)) {
      selectedSectionId = null;
    }
  }

  String? get selectedMarker =>
      selectedPlantId ??
      (selectedSectionId == null ? null : 'section-label-$selectedSectionId');

  Future<void> hideName() async {
    final id = selectedMarker;
    if (id != null && controller != null) {
      try {
        await controller!.hideMarkerInfoWindow(MarkerId(id));
      } catch (_) {
        /* The map may have been disposed during navigation. */
      }
    }
  }

  Future<void> showName() async {
    final id = selectedMarker;
    if (id != null && controller != null && mounted) {
      try {
        await controller!.showMarkerInfoWindow(MarkerId(id));
      } catch (_) {
        /* A remounted map will show its selected name when ready. */
      }
    }
  }

  void tapPlant(String id) {
    if (widget.onPlant == null ||
        !widget.plants.any((p) => p.id == id && visible(p))) {
      return;
    }
    hideName();
    if (selectedPlantId == id) {
      setState(() => selectedPlantId = null);
      widget.onPlant!(id);
    } else {
      setState(() {
        selectedPlantId = id;
        selectedSectionId = null;
      });
      showName();
    }
  }

  void tapSection(String id) {
    if (widget.onSection == null) return;
    hideName();
    if (selectedSectionId == id) {
      setState(() => selectedSectionId = null);
      widget.onSection!(id);
    } else {
      setState(() {
        selectedSectionId = id;
        selectedPlantId = null;
      });
      showName();
    }
  }

  void tapMap(Coordinates point) {
    hideName();
    if (selectedMarker != null) {
      setState(() {
        selectedPlantId = null;
        selectedSectionId = null;
      });
    }
    widget.onTap?.call(point);
  }

  LatLng point(Coordinates p) => LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context) {
    final OrchardMap(
      :sections,
      :plants,
      :draft,
      :draftKind,
      :center,
      :selected,
      :span,
      :onPlant,
      :onSection,
      :onMapCreated,
      :onCameraMove,
      :onMoveVertex,
      :initialCamera,
      :onCameraChanged,
      :onSelectedMoved,
    ) = widget;
    final visiblePlants = plants
        .where((p) => p.status == ItemStatus.active && p.sectionId == null)
        .toList();
    final targetPoint =
        center ??
        selected ??
        plants.firstOrNull?.location ??
        sections.firstOrNull?.vertices.first;
    final size = markerSizeForZoom(
      cameraZoom ?? initialCamera?.zoom ?? (targetPoint == null ? 2 : 19),
    );
    if (!ref.watch(mapsConfiguredProvider)) {
      final sketch = Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(6),
            child: Text(
              'Google Maps is not configured in this build. Coordinate sketch available offline.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: LayoutCanvas(
              sections: sections,
              plants: visiblePlants,
              draft: draft,
              center: center,
              selected: selected,
              span: span,
              iconSize: size,
              onTap: tapMap,
              onPlant: onPlant == null ? null : tapPlant,
              onSection: onSection == null ? null : tapSection,
              selectedPlantId: selectedPlantId,
              selectedSectionId: selectedSectionId,
            ),
          ),
        ],
      );
      return sketch;
    }
    final symbols = ref.watch(markerSymbolsProvider).valueOrNull;
    final taxonomy = ref.watch(taxonomyProvider);
    final taxa = taxonomy.taxa;
    final customIcons = ref.watch(mapIconsProvider).valueOrNull ?? <MapIcon>[];
    BitmapDescriptor iconFor(PlantSymbol symbol, String? customId) {
      final custom = customIcons.where((i) => i.id == customId).firstOrNull;
      if (custom != null && !custom.deleted) {
        final dimensions = ByteData.sublistView(custom.png);
        final w = dimensions.getUint32(16), h = dimensions.getUint32(20);
        final longest = w > h ? w : h;
        return BitmapDescriptor.bytes(
          custom.png,
          width: size * w / longest,
          height: size * h / longest,
        );
      }
      final builtIn = symbols?[customId != null ? PlantSymbol.unknown : symbol];
      if (builtIn is BytesMapBitmap) {
        return BitmapDescriptor.bytes(
          builtIn.byteData,
          width: size,
          height: size,
        );
      }
      return BitmapDescriptor.bytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
        ),
        width: size,
        height: size,
      );
    }

    Taxon? appearance(String id) =>
        taxa.any((t) => t.id == id) ? taxonomy.iconFor(id) : null;
    final target =
        center ??
        selected ??
        plants.firstOrNull?.location ??
        sections.firstOrNull?.vertices.first;
    final map = GoogleMap(
      mapType: MapType.satellite,
      initialCameraPosition:
          initialCamera ??
          CameraPosition(
            target: target == null ? const LatLng(0, 0) : point(target),
            zoom: target == null ? 2 : 19,
          ),
      onMapCreated: (mapController) {
        controller = mapController;
        onMapCreated?.call(mapController);
        showName();
      },
      onCameraMove: (p) {
        if (markerSizeForZoom(p.zoom) !=
            markerSizeForZoom(
              cameraZoom ??
                  initialCamera?.zoom ??
                  (targetPoint == null ? 2 : 19),
            )) {
          setState(() => cameraZoom = p.zoom);
        } else {
          cameraZoom = p.zoom;
        }
        onCameraChanged?.call(p);
        onCameraMove?.call(Coordinates(p.target.latitude, p.target.longitude));
      },
      onTap: (p) => tapMap(Coordinates(p.latitude, p.longitude)),
      // Drawing inside the section form must receive gestures before its ListView.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      mapToolbarEnabled: false,
      padding: const EdgeInsets.only(bottom: 90),
      polylines: {
        for (final s in sections.where((s) => s.kind == SectionKind.row))
          Polyline(
            polylineId: PolylineId(s.id),
            points: s.vertices.map(point).toList(),
            color: Color(s.color),
            width: 4,
            consumeTapEvents: onSection != null,
            onTap: () => tapSection(s.id),
          ),
        if (draft.length >= 2 && draftKind == SectionKind.row)
          Polyline(
            polylineId: const PolylineId('draft'),
            points: draft.map(point).toList(),
            color: Colors.orangeAccent,
            width: 5,
          ),
      },
      polygons: {
        for (final s in sections.where((s) => s.kind != SectionKind.row))
          Polygon(
            polygonId: PolygonId(s.id),
            points: s.vertices.map(point).toList(),
            fillColor: Color(s.color).withValues(alpha: 0.2),
            strokeColor: Color(s.color),
            strokeWidth: 2,
            consumeTapEvents: onSection != null,
            onTap: () => tapSection(s.id),
          ),
        if (draftKind != SectionKind.row && draft.length >= 2)
          Polygon(
            polygonId: const PolygonId('draft'),
            points: draft.map(point).toList(),
            fillColor: Colors.orange.withValues(alpha: 0.2),
            strokeColor: Colors.orangeAccent,
            strokeWidth: 3,
          ),
      },
      markers: {
        // Native info windows remain attached while the map moves. A transparent
        // anchor gives shapes without an optional icon the same name behavior.
        for (final s in sections)
          Marker(
            markerId: MarkerId('section-label-${s.id}'),
            position: point(sectionCenter(s)),
            icon: BitmapDescriptor.bytes(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
              ),
              width: 1,
              height: 1,
            ),
            consumeTapEvents: true,
            infoWindow: InfoWindow(
              title: s.name,
              onTap: () => tapSection(s.id),
            ),
            onTap: () => tapSection(s.id),
          ),
        for (final s in sections)
          if (s.symbol != null || s.customIconId != null)
            Marker(
              markerId: MarkerId('section-icon-${s.id}'),
              position: point(sectionCenter(s)),
              icon: iconFor(s.symbol ?? PlantSymbol.tree, s.customIconId),
              anchor: const Offset(.5, .5),
              consumeTapEvents: true,
              infoWindow: InfoWindow(
                title: s.name,
                onTap: () => tapSection(s.id),
              ),
              onTap: () => tapSection(s.id),
            ),
        for (final s in sections.where((s) => s.kind == SectionKind.row)) ...[
          Marker(
            markerId: MarkerId('row-start-${s.id}'),
            position: point(s.vertices.first),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            consumeTapEvents: true,
            infoWindow: InfoWindow(
              title: '${s.name} · Start (1)',
              onTap: () => tapSection(s.id),
            ),
            onTap: () => tapSection(s.id),
          ),
          Marker(
            markerId: MarkerId('row-finish-${s.id}'),
            position: point(s.vertices.last),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            consumeTapEvents: true,
            infoWindow: InfoWindow(
              title: '${s.name} · Finish',
              onTap: () => tapSection(s.id),
            ),
            onTap: () => tapSection(s.id),
          ),
        ],
        for (final p in visiblePlants)
          Marker(
            markerId: MarkerId(p.id),
            position: point(p.location),
            icon: iconFor(
              appearance(p.taxonId)?.symbol ?? PlantSymbol.tree,
              appearance(p.taxonId)?.customIconId,
            ),
            anchor: const Offset(.5, .5),
            infoWindow: InfoWindow(title: p.name, onTap: () => tapPlant(p.id)),
            // Explicit selection preserves first-tap names and second-tap navigation.
            consumeTapEvents: true,
            onTap: () => tapPlant(p.id),
          ),
        if (selected != null)
          Marker(
            markerId: const MarkerId('selected-position'),
            position: point(selected),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(title: 'Selected location'),
            draggable: onSelectedMoved != null,
            onDragEnd: (p) =>
                onSelectedMoved?.call(Coordinates(p.latitude, p.longitude)),
          ),
        for (var i = 0; i < draft.length; i++)
          Marker(
            markerId: MarkerId('draft-$i'),
            position: point(draft[i]),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(title: 'Vertex ${i + 1}'),
            draggable: onMoveVertex != null,
            onDragEnd: (p) =>
                onMoveVertex?.call(i, Coordinates(p.latitude, p.longitude)),
          ),
      },
    );
    return map;
  }
}
