import 'models.dart';
import 'work.dart';

/// Definition edits do not rewrite targets, occurrence identities or completion.
OrchardTask editOpenTask(
  OrchardTask old, {
  required String title,
  required String notes,
  String? dueDate,
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
    status: old.status,
    eventType: eventType,
    eventHarvest: eventHarvest,
  );
}

TaskPlan editPlan(
  TaskPlan old, {
  required String title,
  required String notes,
  String? dueDate,
  ActivityType? eventType,
  Harvest? eventHarvest,
}) => TaskPlan(
  id: old.id,
  propertyId: old.propertyId,
  title: title,
  notes: notes,
  createdAt: old.createdAt,
  target: old.target,
  itemId: old.itemId,
  sectionId: old.sectionId,
  cropId: old.cropId,
  taxonId: old.taxonId,
  sectionKind: old.sectionKind,
  dueDate: old.repeat == RepeatSchedule.none ? dueDate : old.dueDate,
  anchorOn: old.repeat == RepeatSchedule.none
      ? old.anchorOn ?? occurrenceDates(old, DateTime.now()).single
      : old.anchorOn,
  repeat: old.repeat,
  eventType: eventType,
  eventHarvest: eventHarvest,
);
