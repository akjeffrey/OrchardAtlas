import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/providers.dart';
import '../domain/landscape.dart';
import '../domain/models.dart';
import 'layout_canvas.dart';
import 'plant_symbols.dart';

/// The same satellite map is used for browsing and for drawing orchard geometry.
class OrchardMap extends ConsumerWidget {
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

  LatLng point(Coordinates p) => LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mapsConfiguredProvider)) {
      return Column(
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
              plants: plants,
              draft: draft,
              center: center,
              selected: selected,
              span: span,
              onTap: onTap,
              onPlant: onPlant,
              onSection: onSection,
            ),
          ),
        ],
      );
    }
    final symbols = ref.watch(markerSymbolsProvider).valueOrNull;
    final taxa = ref.watch(taxonomyProvider).taxa;
    final target =
        center ??
        selected ??
        plants.firstOrNull?.location ??
        sections.firstOrNull?.vertices.first;
    return GoogleMap(
      mapType: MapType.satellite,
      initialCameraPosition:
          initialCamera ??
          CameraPosition(
            target: target == null ? const LatLng(0, 0) : point(target),
            zoom: target == null ? 2 : 19,
          ),
      onMapCreated: onMapCreated,
      onCameraMove: (p) {
        onCameraChanged?.call(p);
        onCameraMove?.call(Coordinates(p.target.latitude, p.target.longitude));
      },
      onTap: onTap == null
          ? null
          : (p) => onTap!(Coordinates(p.latitude, p.longitude)),
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
            color: Colors.lightBlueAccent,
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
            fillColor: Colors.green.withValues(alpha: 0.2),
            strokeColor: Colors.lightGreenAccent,
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
        for (final p in plants)
          Marker(
            markerId: MarkerId(p.id),
            position: point(p.location),
            icon:
                symbols?[taxa
                        .where((t) => t.id == p.taxonId)
                        .firstOrNull
                        ?.symbol ??
                    PlantSymbol.tree] ??
                BitmapDescriptor.defaultMarker,
            infoWindow: InfoWindow(title: p.name),
            onTap: () => onPlant?.call(p.id),
          ),
        if (selected != null)
          Marker(
            markerId: const MarkerId('selected-position'),
            position: point(selected!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(title: 'Selected location'),
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
  }
}
