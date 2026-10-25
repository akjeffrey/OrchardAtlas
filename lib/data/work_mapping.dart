import '../domain/models.dart';
import '../domain/landscape.dart';
import '../domain/work.dart';
import 'landscape_mapping.dart';

class WorkMapping {
  static Map<String, dynamic> plan(TaskPlan p, {bool native = false}) => {
    'schemaVersion': 1,
    'title': p.title,
    'target': p.target,
    'itemId': p.itemId,
    'sectionId': p.sectionId,
    'cropId': p.cropId,
    'taxonId': p.taxonId,
    'sectionKind': p.sectionKind.name,
    'dueDate': p.dueDate,
    'repeat': p.repeat.name,
    if (p.anchorOn != null) 'anchorOn': p.anchorOn,
    'eventType': p.eventType?.name,
    'eventHarvest': p.eventHarvest == null
        ? null
        : {
            'quantity': p.eventHarvest!.quantity,
            'unit': p.eventHarvest!.unit.name,
          },
    'notes': p.notes,
    'createdAt': LandscapeMapping.time(p.createdAt, native),
  };
  static TaskPlan readPlan(
    String property,
    String id,
    Map<String, dynamic> d,
  ) => TaskPlan(
    id: id,
    propertyId: property,
    title: d['title'] as String,
    target: d['target'] as String,
    createdAt: LandscapeMapping.readTime(d['createdAt'] as Object),
    itemId: d['itemId'] as String?,
    sectionId: d['sectionId'] as String?,
    cropId: d['cropId'] as String?,
    taxonId: d['taxonId'] as String?,
    sectionKind: d['sectionKind'] == 'bed'
        ? SectionKind.area
        : SectionKind.values.byName(d['sectionKind'] as String? ?? 'row'),
    dueDate: d['dueDate'] as String?,
    anchorOn: d['anchorOn'] as String?,
    repeat: RepeatSchedule.values.byName(d['repeat'] as String? ?? 'none'),
    eventType: d['eventType'] == null
        ? null
        : ActivityType.values.byName(d['eventType'] as String),
    eventHarvest: d['eventHarvest'] == null
        ? null
        : Harvest(
            (d['eventHarvest']['quantity'] as num).toDouble(),
            HarvestUnit.values.byName(d['eventHarvest']['unit'] as String),
          ),
    notes: d['notes'] as String? ?? '',
  );
}
