import 'package:uuid/uuid.dart';

import 'models.dart';
import 'work.dart';

/// Definition edits do not rewrite targets, occurrence identities or completion.
OrchardTask editOpenTask(
  OrchardTask old, {
  required String title,
  required String notes,
  String? dueDate,
  String? endDate,
  ActivityType? eventType,
  Harvest? eventHarvest,
}) {
  if (old.status != TaskStatus.open) return old;
  return OrchardTask(
    id: old.id,
    propertyId: old.propertyId,
    title: title,
    notes: notes,
    createdAt: old.createdAt,
    itemId: old.itemId,
    sectionId: old.sectionId,
    cropId: old.cropId,
    groupId: old.groupId,
    groupScope: old.groupScope,
    planId: old.planId,
    occurrenceOn: old.occurrenceOn,
    dueDate: dueDate,
    endDate: endDate,
    status: old.status,
    membershipExcluded: old.membershipExcluded,
    eventType: eventType,
    eventHarvest: eventHarvest,
  );
}

TaskPlan editPlan(
  TaskPlan old, {
  required String title,
  required String notes,
  String? dueDate,
  String? endDate,
  ActivityType? eventType,
  Harvest? eventHarvest,
  String? target,
  String? taxonId,
  bool updateTargets = false,
  List<String>? includedTargets,
  List<String>? excludedTargets,
  DateTime? now,
  String? newScheduleId,
}) {
  final today = now ?? DateTime.now();
  final start = old.repeat == RepeatSchedule.none
      ? dueDate
      : dueDate ?? old.dueDate;
  final changed = start != old.dueDate;
  final oldCurrent = taskOccurrences(old, today).last;
  final draft = TaskPlan(
    id: old.id,
    propertyId: old.propertyId,
    title: title,
    notes: notes,
    createdAt: old.createdAt,
    target: target ?? old.target,
    itemId: !updateTargets || target == 'plant' ? old.itemId : null,
    sectionId: !updateTargets || target == 'section' || target == old.target
        ? old.sectionId
        : null,
    cropId: !updateTargets || target == 'crop' ? old.cropId : null,
    taxonId: updateTargets
        ? (['plants', 'crops'].contains(target) ? taxonId : null)
        : old.taxonId,
    sectionKind: old.sectionKind,
    dueDate: start,
    endDate: endDate,
    anchorOn:
        old.anchorOn ??
        (old.repeat == RepeatSchedule.none ? oldCurrent.key : null),
    repeat: old.repeat,
    eventType: eventType,
    eventHarvest: eventHarvest,
    includedTargets: includedTargets ?? old.includedTargets,
    excludedTargets: excludedTargets ?? old.excludedTargets,
    legacyIds: old.legacyIds,
  );
  final date = taskOccurrences(draft, today).last.startsOn;
  return TaskPlan(
    id: draft.id,
    propertyId: draft.propertyId,
    title: draft.title,
    notes: draft.notes,
    createdAt: draft.createdAt,
    target: draft.target,
    itemId: draft.itemId,
    sectionId: draft.sectionId,
    cropId: draft.cropId,
    taxonId: draft.taxonId,
    sectionKind: draft.sectionKind,
    dueDate: draft.dueDate,
    endDate: draft.endDate,
    anchorOn: draft.anchorOn,
    repeat: draft.repeat,
    eventType: draft.eventType,
    eventHarvest: draft.eventHarvest,
    includedTargets: draft.includedTargets,
    excludedTargets: draft.excludedTargets,
    legacyIds: draft.legacyIds,
    scheduleId: changed && old.repeat != RepeatSchedule.none
        ? newScheduleId ?? const Uuid().v4()
        : old.scheduleId,
    scheduleFrom: changed && old.repeat != RepeatSchedule.none
        ? date
        : old.scheduleFrom,
    currentKey: changed && old.repeat != RepeatSchedule.none
        ? oldCurrent.key
        : old.currentKey,
    generateFrom: changed || updateTargets ? date : old.generateFrom,
  );
}

TaskPlan planForLegacyTask(OrchardTask task, List<OrchardTask> tasks) {
  final members = task.groupId == null
      ? [task]
      : tasks.where((t) => t.propertyId == task.propertyId && t.groupId == task.groupId).toList();
  final keys = members
      .map(taskTargetKey)
      .where((k) => k != 'property')
      .toList();
  return TaskPlan(
    id: task.groupId ?? task.id,
    propertyId: task.propertyId,
    title: task.title,
    notes: task.notes,
    createdAt: task.createdAt,
    target: keys.isEmpty ? 'property' : 'manual',
    dueDate: task.dueDate,
    endDate: task.endDate,
    anchorOn:
        task.occurrenceOn ??
        task.dueDate ??
        calendarDate(task.createdAt.toLocal()),
    includedTargets: keys,
    legacyIds: members.map((t) => t.id).toList(),
    eventType: task.eventType,
    eventHarvest: task.eventHarvest,
  );
}

TaskPlan deletedTaskPlan(TaskPlan p) => TaskPlan(
  id: p.id,
  propertyId: p.propertyId,
  title: p.title,
  createdAt: p.createdAt,
  target: p.target,
  itemId: p.itemId,
  sectionId: p.sectionId,
  cropId: p.cropId,
  taxonId: p.taxonId,
  dueDate: p.dueDate,
  endDate: p.endDate,
  anchorOn: p.anchorOn,
  repeat: p.repeat,
  sectionKind: p.sectionKind,
  eventType: p.eventType,
  eventHarvest: p.eventHarvest,
  notes: p.notes,
  deleted: true,
  includedTargets: p.includedTargets,
  excludedTargets: p.excludedTargets,
  legacyIds: p.legacyIds,
  scheduleId: p.scheduleId,
  scheduleFrom: p.scheduleFrom,
  currentKey: p.currentKey,
  generateFrom: p.generateFrom,
);
