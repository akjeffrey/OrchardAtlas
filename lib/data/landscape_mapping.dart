import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';
import '../domain/landscape.dart';
import 'firestore_mapping.dart';

class LandscapeMapping {
  static Object time(DateTime date, bool native) =>
      native ? Timestamp.fromDate(date) : date.toIso8601String();
  static DateTime readTime(Object value) => value is Timestamp
      ? value.toDate().toUtc()
      : DateTime.parse(value as String).toUtc();
  static Map<String, dynamic> section(
    OrchardSection s, {
    bool native = false,
  }) => {
    'schemaVersion': 1,
    'name': s.name,
    'kind': s.kind.name,
    'color': s.color,
    'symbol': s.symbol?.name,
    'parentId': s.parentId,
    'notes': s.notes,
    'createdAt': time(s.createdAt, native),
    'vertices': [
      for (final p in s.vertices)
        if (native)
          GeoPoint(p.latitude, p.longitude)
        else
          {'lat': p.latitude, 'lon': p.longitude},
    ],
  };
  static OrchardSection readSection(
    String propertyId,
    String id,
    Map<String, dynamic> d,
  ) {
    FirestoreMapping.version(d);
    return OrchardSection(
      id: id,
      propertyId: propertyId,
      name: d['name'] as String,
      kind: d['kind'] == 'bed'
          ? SectionKind.area
          : SectionKind.values.byName(d['kind'] as String),
      color: (d['color'] as num?)?.toInt() ?? 0xff4caf50,
      symbol: d['symbol'] == null
          ? null
          : PlantSymbol.values.byName(d['symbol'] as String),
      parentId: d['parentId'] as String?,
      notes: d['notes'] as String,
      createdAt: readTime(d['createdAt'] as Object),
      vertices: [
        for (final p in d['vertices'] as List)
          if (p is GeoPoint)
            Coordinates(p.latitude, p.longitude)
          else
            Coordinates(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ),
      ],
    );
  }

  static Map<String, dynamic> crop(CropPlanting c, {bool native = false}) => {
    'schemaVersion': 1,
    'sectionId': c.sectionId,
    'taxonId': c.taxonId,
    'label': c.label,
    'season': c.season,
    'notes': c.notes,
    'plantedOn': c.plantedOn,
    'harvestedOn': c.harvestedOn,
    'status': c.status.name,
    'createdAt': time(c.createdAt, native),
  };
  static CropPlanting readCrop(
    String propertyId,
    String id,
    Map<String, dynamic> d,
  ) {
    FirestoreMapping.version(d);
    return CropPlanting(
      id: id,
      propertyId: propertyId,
      sectionId: d['sectionId'] as String,
      taxonId: d['taxonId'] as String,
      label: d['label'] as String,
      season: d['season'] as String,
      notes: d['notes'] as String,
      plantedOn: d['plantedOn'] as String?,
      harvestedOn: d['harvestedOn'] as String?,
      status: CropStatus.values.byName(d['status'] as String),
      createdAt: readTime(d['createdAt'] as Object),
    );
  }

  static Map<String, dynamic> harvest(CropHarvest h, {bool native = false}) => {
    'schemaVersion': 1,
    'cropId': h.cropId,
    'activityDate': h.activityDate,
    'notes': h.notes,
    'recordedAt': time(h.recordedAt, native),
    'harvest': {'quantity': h.harvest.quantity, 'unit': h.harvest.unit.name},
  };
  static CropHarvest readHarvest(
    String propertyId,
    String id,
    Map<String, dynamic> d,
  ) {
    FirestoreMapping.version(d);
    return CropHarvest(
      id: id,
      propertyId: propertyId,
      cropId: d['cropId'] as String,
      activityDate: d['activityDate'] as String,
      notes: d['notes'] as String,
      recordedAt: readTime(d['recordedAt'] as Object),
      harvest: Harvest(
        (d['harvest']['quantity'] as num).toDouble(),
        HarvestUnit.values.byName(d['harvest']['unit'] as String),
      ),
    );
  }
}
