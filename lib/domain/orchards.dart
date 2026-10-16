import 'models.dart';

abstract interface class OrchardDirectoryRepository {
  Stream<List<Place>> watchPlaces(String userId);
  Future<Place> createPlace(String userId, String name);
  Future<Place> renamePlace(String userId, String placeId, String name);
  Future<void> selectPlace(String userId, String placeId);
}

class OrchardMapView {
  OrchardMapView({
    required this.center,
    required this.zoom,
    this.bearing = 0,
    this.tilt = 0,
    this.fullScreen = false,
  }) {
    if (!zoom.isFinite ||
        zoom < 0 ||
        zoom > 24 ||
        !bearing.isFinite ||
        bearing < 0 ||
        bearing > 360 ||
        !tilt.isFinite ||
        tilt < 0 ||
        tilt > 90) {
      throw ArgumentError('Invalid map view');
    }
  }
  final Coordinates center;
  final double zoom, bearing, tilt;
  final bool fullScreen;
}

abstract interface class MapViewRepository {
  Future<String?> loadTaskSort(String userId);
  Future<void> saveTaskSort(String userId, String value);
  Future<OrchardMapView?> load(String userId, String orchardId);
  Future<void> save(String userId, String orchardId, OrchardMapView view);
}
