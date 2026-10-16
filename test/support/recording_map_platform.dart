import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Records native map commands while allowing native initialization to be delayed.
class RecordingMapPlatform extends GoogleMapsFlutterPlatform {
  // Create the future inside the widget test zone, not its outer setUp zone.
  late final initialize = Completer<void>();
  final cameras = <Object>[];
  final disposed = <int>[];
  final created = <int>{};
  final pendingViews = <int, PlatformViewCreatedCallback>{};
  void attachPendingViews() {
    final views = Map<int, PlatformViewCreatedCallback>.of(pendingViews);
    pendingViews.clear();
    for (final entry in views.entries) {
      entry.value(entry.key);
    }
  }

  @override
  Future<void> init(int mapId) => initialize.future;
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    if (created.add(creationId)) {
      pendingViews[creationId] = onPlatformViewCreated;
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> animateCamera(
    CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    cameras.add(cameraUpdate.toJson());
  }

  @override
  void dispose({required int mapId}) => disposed.add(mapId);
  @override
  Future<void> updateMapConfiguration(
    MapConfiguration configuration, {
    required int mapId,
  }) async {}
  @override
  Future<void> updateMarkers(
    MarkerUpdates markerUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updatePolygons(
    PolygonUpdates polygonUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updatePolylines(
    PolylineUpdates polylineUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updateCircles(
    CircleUpdates circleUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updateHeatmaps(
    HeatmapUpdates heatmapUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updateTileOverlays({
    required Set<TileOverlay> newTileOverlays,
    required int mapId,
  }) async {}
  @override
  Future<void> updateClusterManagers(
    ClusterManagerUpdates clusterManagerUpdates, {
    required int mapId,
  }) async {}
  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}
  @override
  Stream<CameraMoveStartedEvent> onCameraMoveStarted({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<CameraMoveEvent> onCameraMove({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<CameraIdleEvent> onCameraIdle({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<MarkerTapEvent> onMarkerTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<MarkerDragEvent> onMarkerDrag({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<PolylineTapEvent> onPolylineTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<PolygonTapEvent> onPolygonTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<CircleTapEvent> onCircleTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<PointOfInterestTapEvent> onPointOfInterestTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<MapTapEvent> onTap({required int mapId}) => const Stream.empty();
  @override
  Stream<MapLongPressEvent> onLongPress({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<ClusterTapEvent> onClusterTap({required int mapId}) =>
      const Stream.empty();
  @override
  Stream<GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      const Stream.empty();
}
