import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/orchards.dart';

class DeviceMapViewRepository implements MapViewRepository {
  DeviceMapViewRepository(this.preferences);
  final SharedPreferences preferences;
  String _key(String user, String orchard) => 'map-default:$user:$orchard';
  @override
  Future<OrchardMapView?> load(String userId, String orchardId) async {
    final raw = preferences.getString(_key(userId, orchardId));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return OrchardMapView(
        center: Coordinates(
          (data['latitude'] as num).toDouble(),
          (data['longitude'] as num).toDouble(),
        ),
        zoom: (data['zoom'] as num).toDouble(),
        bearing: (data['bearing'] as num).toDouble(),
        tilt: (data['tilt'] as num).toDouble(),
        fullScreen: data['fullScreen'] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(
    String userId,
    String orchardId,
    OrchardMapView view,
  ) async {
    final success = await preferences.setString(
      _key(userId, orchardId),
      jsonEncode({
        'latitude': view.center.latitude,
        'longitude': view.center.longitude,
        'zoom': view.zoom,
        'bearing': view.bearing,
        'tilt': view.tilt,
        'fullScreen': view.fullScreen,
      }),
    );
    if (!success) throw StateError('Could not save default map view');
  }
}
