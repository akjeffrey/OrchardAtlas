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
  String? selectedPlantId;
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
  }

  void tapPlant(String id) {
    if (widget.onPlant == null ||
        !widget.plants.any((p) => p.id == id && visible(p))) {
      return;
    }
    if (selectedPlantId == id) {
      // Reset before navigation, including for a rapid sequence of tap events.
      setState(() => selectedPlantId = null);
      widget.onPlant!(id);
    } else {
      setState(() => selectedPlantId = id);
    }
  }

  void tapMap(Coordinates point) {
    if (selectedPlantId != null) setState(() => selectedPlantId = null);
    widget.onTap?.call(point);
  }

  Widget withPlantName(Widget map) {
    final plant = widget.plants
        .where((p) => p.id == selectedPlantId && visible(p))
        .firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        if (plant != null)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        plant.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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
              onSection: onSection,
            ),
          ),
        ],
      );
      return withPlantName(sketch);
    }
    final symbols = ref.watch(markerSymbolsProvider).valueOrNull;
    final taxonomy = ref.watch(taxonomyProvider);
    final taxa = taxonomy.taxa;
    final customIcons = ref.watch(mapIconsProvider).valueOrNull ?? <MapIcon>[];
    BitmapDescriptor iconFor(PlantSymbol symbol, String? customId) {
      final custom = customIcons.where((i) => i.id == customId).firstOrNull;
      if (custom != null) {
        final dimensions = ByteData.sublistView(custom.png);
        final w = dimensions.getUint32(16), h = dimensions.getUint32(20);
        final longest = w > h ? w : h;
        return BitmapDescriptor.bytes(
          custom.png,
          width: size * w / longest,
          height: size * h / longest,
        );
      }
      final builtIn = symbols?[symbol];
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
      onMapCreated: onMapCreated,
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
            onTap: () => onSection?.call(s.id),
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
            onTap: () => onSection?.call(s.id),
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
        for (final s in sections)
          if (s.symbol != null || s.customIconId != null)
            Marker(
              markerId: MarkerId('section-icon-${s.id}'),
              position: point(sectionCenter(s)),
              icon: iconFor(s.symbol ?? PlantSymbol.tree, s.customIconId),
              anchor: const Offset(.5, .5),
              infoWindow: InfoWindow(title: s.name),
              onTap: () => onSection?.call(s.id),
            ),
        for (final s in sections.where((s) => s.kind == SectionKind.row)) ...[
          Marker(
            markerId: MarkerId('row-start-${s.id}'),
            position: point(s.vertices.first),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(title: '${s.name} · Start (1)'),
            onTap: () => onSection?.call(s.id),
          ),
          Marker(
            markerId: MarkerId('row-finish-${s.id}'),
            position: point(s.vertices.last),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: '${s.name} · Finish'),
            onTap: () => onSection?.call(s.id),
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
            infoWindow: InfoWindow(title: p.name),
            // Flutter shows the name consistently on native maps and sketches.
            // Consume native taps so automatic info windows cannot navigate too.
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
    return withPlantName(map);
  }
}
