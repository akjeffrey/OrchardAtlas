import 'package:flutter/services.dart';

import '../domain/map_search.dart';
import '../domain/models.dart';

/// Uses the operating system geocoder, independently of Firebase and Maps billing.
class DeviceAddressSearchRepository implements AddressSearchRepository {
  static const channel = MethodChannel('orchard_atlas/map_services');

  static Future<bool> mapsConfigured() async {
    try {
      return await channel.invokeMethod<bool>('mapsConfigured') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<MapLocation>> search(String address) async {
    final results = await channel
        .invokeListMethod<Object?>('searchAddress', {'query': address})
        .timeout(const Duration(seconds: 20));
    return [
      for (final result in results ?? [])
        if (result is Map)
          MapLocation(
            result['label'] as String,
            Coordinates(
              (result['latitude'] as num).toDouble(),
              (result['longitude'] as num).toDouble(),
            ),
          ),
    ];
  }
}
