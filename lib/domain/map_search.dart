import 'models.dart';

class MapLocation {
  const MapLocation(this.label, this.coordinates);
  final String label;
  final Coordinates coordinates;
}

abstract interface class AddressSearchRepository {
  Future<List<MapLocation>> search(String address);
}

/// Decimal degrees, latitude first. Parsing coordinates never calls a service.
Coordinates? parseMapCoordinates(String query) {
  const number = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)';
  final match = RegExp('^($number)\\s*(?:,\\s*|\\s+)($number)\$')
      .firstMatch(query.trim());
  if (match == null) return null;
  return Coordinates(double.parse(match[1]!), double.parse(match[2]!));
}
