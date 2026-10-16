import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';

class FirestoreMapping {
  static Map<String, dynamic> taxonToMap(Taxon t) => {
    'schemaVersion': 1,
    'name': t.name,
    'rank': t.rank.name,
    'parentId': t.parentId,
    'symbol': t.symbol.name,
  };
  static Taxon taxonFromMap(String id, Map<String, dynamic> d) {
    version(d);
    return Taxon(
      id: id,
      name: d['name'] as String,
      rank: TaxonRank.values.byName(d['rank'] as String),
      parentId: d['parentId'] as String?,
      symbol: PlantSymbol.values.byName(d['symbol'] as String),
    );
  }

  static void version(Map<String, dynamic> data) {
    if (data['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported record version; update OrchardAtlas',
      );
    }
  }

  static Map<String, dynamic> placeToMap(Place p) => {
    'schemaVersion': 1,
    'name': p.name,
    'ownerId': p.ownerId,
    'createdAt': Timestamp.fromDate(p.createdAt),
  };
  static Place placeFromMap(String id, Map<String, dynamic> d) {
    version(d);
    return Place(
      id: id,
      name: d['name'] as String,
      ownerId: d['ownerId'] as String,
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  static Map<String, dynamic> plantToMap(ManagedPlant p) => {
    'schemaVersion': 1,
    'kind': p.kind.name,
    'name': p.name,
    'taxonId': p.taxonId,
    'location': GeoPoint(p.location.latitude, p.location.longitude),
    'createdAt': Timestamp.fromDate(p.createdAt),
  };
  static ManagedPlant plantFromMap(
    String propertyId,
    String id,
    Map<String, dynamic> d,
  ) {
    version(d);
    if (d['kind'] != ItemKind.managedPlant.name) {
      throw const FormatException('Unsupported tracked item kind');
    }
    final point = d['location'] as GeoPoint;
    return ManagedPlant(
      id: id,
      propertyId: propertyId,
      name: d['name'] as String,
      taxonId: d['taxonId'] as String,
      location: Coordinates(point.latitude, point.longitude),
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  static Map<String, dynamic> eventToMap(PlantEvent e) => {
    'schemaVersion': 1,
    'authorId': e.authorId,
    'type': e.type.name,
    'occurredAt': Timestamp.fromDate(e.occurredAt),
    'activityDate': e.activityDate,
    'recordedAt': Timestamp.fromDate(e.recordedAt),
    'notes': e.notes,
    if (e.harvest != null)
      'harvest': {
        'quantity': e.harvest!.quantity,
        'unit': e.harvest!.unit.name,
      },
  };
  static PlantEvent eventFromMap(
    String propertyId,
    String itemId,
    String id,
    Map<String, dynamic> d,
  ) {
    version(d);
    final harvest = d['harvest'] as Map<String, dynamic>?;
    return PlantEvent(
      id: id,
      propertyId: propertyId,
      itemId: itemId,
      authorId: d['authorId'] as String,
      type: ActivityType.values.byName(d['type'] as String),
      occurredAt: (d['occurredAt'] as Timestamp).toDate().toUtc(),
      activityDate: d['activityDate'] as String,
      recordedAt: (d['recordedAt'] as Timestamp).toDate().toUtc(),
      notes: d['notes'] as String,
      harvest: harvest == null
          ? null
          : Harvest(
              (harvest['quantity'] as num).toDouble(),
              HarvestUnit.values.byName(harvest['unit'] as String),
            ),
    );
  }
}
