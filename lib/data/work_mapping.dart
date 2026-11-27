import '../domain/models.dart';
import '../domain/landscape.dart';
import '../domain/work.dart';
import 'landscape_mapping.dart';

class WorkMapping {
  static Map<String, dynamic> plan(TaskPlan p, {bool native = false}) => {
    'schemaVersion': 1,
    if (p.deleted) 'deleted': true,
    if (p.includedTargets.isNotEmpty) 'includedTargets': p.includedTargets,
    if (p.excludedTargets.isNotEmpty) 'excludedTargets': p.excludedTargets,
    if (p.legacyIds.isNotEmpty) 'legacyIds': p.legacyIds,
    if (p.scheduleId != null) 'scheduleId': p.scheduleId,
    if (p.scheduleFrom != null) 'scheduleFrom': p.scheduleFrom,
    if (p.currentKey != null) 'currentKey': p.currentKey,
    if (p.generateFrom != null) 'generateFrom': p.generateFrom,
    'title': p.title,
    'target': p.target,
    'itemId': p.itemId,
    'sectionId': p.sectionId,
    'cropId': p.cropId,
    'taxonId': p.taxonId,
    'sectionKind': p.sectionKind.name,
    'dueDate': p.dueDate,
    'endDate': p.endDate,
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
    deleted: d['deleted'] as bool? ?? false,
    includedTargets: List<String>.from(d['includedTargets'] as List? ?? []),
    excludedTargets: List<String>.from(d['excludedTargets'] as List? ?? []),
    legacyIds: List<String>.from(d['legacyIds'] as List? ?? []),
    scheduleId: d['scheduleId'] as String?,
    scheduleFrom: d['scheduleFrom'] as String?,
    currentKey: d['currentKey'] as String?,
    generateFrom: d['generateFrom'] as String?,
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
    endDate: d['endDate'] as String?,
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
