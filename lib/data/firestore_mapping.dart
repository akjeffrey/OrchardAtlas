import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';

class FirestoreMapping {
  static Map<String, dynamic> taxonToMap(Taxon t) => {
    'schemaVersion': 1,
    'name': t.name,
    'rank': t.rank.name,
    'parentId': t.parentId,
    'symbol': t.symbol.name,
    'customIconId': t.customIconId,
    'iconOverride': t.iconOverride,
    'scientificName': t.scientificName,
  };
  static Taxon taxonFromMap(String id, Map<String, dynamic> d) {
    version(d);
    return Taxon(
      id: id,
      name: d['name'] as String,
      rank: TaxonRank.values.byName(d['rank'] as String),
      parentId: d['parentId'] as String?,
      symbol: PlantSymbol.values.byName(d['symbol'] as String),
      customIconId: d['customIconId'] as String?,
      iconOverride: d['iconOverride'] as bool?,
      scientificName: d['scientificName'] as String?,
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
    ...plantMetadataToMap(p),
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
      sectionId: d['sectionId'] as String?,
      rowOrder: (d['rowOrder'] as num?)?.toDouble(),
      plantedOn: d['plantedOn'] as String?,
      rootstock: d['rootstock'] as String? ?? '',
      nursery: d['nursery'] as String? ?? '',
      notes: d['notes'] as String? ?? '',
      status: ItemStatus.values.byName(d['status'] as String? ?? 'active'),
      accuracyMeters: (d['accuracyMeters'] as num?)?.toDouble(),
      name: d['name'] as String,
      taxonId: d['taxonId'] as String,
      location: Coordinates(point.latitude, point.longitude),
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  static Map<String, dynamic> plantMetadataToMap(ManagedPlant p) => {
    if (p.sectionId != null) 'sectionId': p.sectionId,
    'plantedOn': p.plantedOn,
    'rowOrder': p.rowOrder,
    'rootstock': p.rootstock,
    'nursery': p.nursery,
    'notes': p.notes,
    'status': p.status.name,
    'accuracyMeters': p.accuracyMeters,
  };
  static Map<String, dynamic> editablePlantToMap(ManagedPlant p) => {
    'name': p.name,
    'taxonId': p.taxonId,
    'location': GeoPoint(p.location.latitude, p.location.longitude),
    'plantedOn': p.plantedOn,
    'accuracyMeters': p.accuracyMeters,
    'rowOrder': p.rowOrder,
    'sectionId': p.sectionId,
    'rootstock': p.rootstock,
    'nursery': p.nursery,
    'notes': p.notes,
    'status': p.status.name,
  };
  static Map<String, dynamic> taskExtrasToMap(OrchardTask t) => {
    if (t.sectionId != null) 'sectionId': t.sectionId,
    if (t.cropId != null) 'cropId': t.cropId,
    if (t.groupId != null) 'groupId': t.groupId,
    if (t.groupScope.isNotEmpty) 'groupScope': t.groupScope,
    'completedOn': t.completedOn,
    'planId': t.planId,
    'occurrenceOn': t.occurrenceOn,
    'eventType': t.eventType?.name,
    'eventHarvest': t.eventHarvest == null
        ? null
        : {
            'quantity': t.eventHarvest!.quantity,
            'unit': t.eventHarvest!.unit.name,
          },
  };
  static Map<String, dynamic> taskToMap(OrchardTask t) => {
    'schemaVersion': 1,
    ...taskExtrasToMap(t),
    'title': t.title,
    'notes': t.notes,
    'itemId': t.itemId,
    'dueDate': t.dueDate,
    'status': t.status.name,
    'createdAt': Timestamp.fromDate(t.createdAt),
  };
  static OrchardTask taskFromMap(
    String propertyId,
    String id,
    Map<String, dynamic> d,
  ) {
    version(d);
    return OrchardTask(
      id: id,
      propertyId: propertyId,
      title: d['title'] as String,
      notes: d['notes'] as String,
      sectionId: d['sectionId'] as String?,
      cropId: d['cropId'] as String?,
      groupId: d['groupId'] as String?,
      groupScope: d['groupScope'] as String? ?? '',
      completedOn: d['completedOn'] as String?,
      planId: d['planId'] as String?,
      occurrenceOn: d['occurrenceOn'] as String?,
      eventType: d['eventType'] == null
          ? null
          : ActivityType.values.byName(d['eventType'] as String),
      eventHarvest: d['eventHarvest'] == null
          ? null
          : Harvest(
              (d['eventHarvest']['quantity'] as num).toDouble(),
              HarvestUnit.values.byName(d['eventHarvest']['unit'] as String),
            ),
      itemId: d['itemId'] as String?,
      dueDate: d['dueDate'] as String?,
      status: TaskStatus.values.byName(d['status'] as String),
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  static Map<String, dynamic> eventToMap(PlantEvent e) => {
    'schemaVersion': 1,
    'authorId': e.authorId,
    if (e.taskId != null) 'taskId': e.taskId,
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
      taskId: d['taskId'] as String?,
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
