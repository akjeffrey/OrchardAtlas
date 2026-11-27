import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'models.dart';
import 'landscape.dart';
import 'taxonomy.dart';

enum RepeatSchedule { none, daily, weekly, monthly, yearly }

enum TaskSort { dueDate, newest, oldest, title, status }

class TaskPlan {
  TaskPlan({
    required this.id,
    required this.propertyId,
    required String title,
    required this.createdAt,
    required this.target,
    this.itemId,
    this.sectionId,
    this.cropId,
    this.taxonId,
    this.sectionKind = SectionKind.row,
    this.dueDate,
    this.endDate,
    this.anchorOn,
    this.repeat = RepeatSchedule.none,
    this.eventType,
    this.eventHarvest,
    this.notes = '',
    this.deleted = false,
    this.scheduleId,
    this.scheduleFrom,
    this.currentKey,
    this.generateFrom,
    List<String> includedTargets = const [],
    List<String> excludedTargets = const [],
    List<String> legacyIds = const [],
  }) : title = requiredText(title, 'Task title'),
       includedTargets = List.unmodifiable(includedTargets.toSet()),
       excludedTargets = List.unmodifiable(excludedTargets.toSet()),
       legacyIds = List.unmodifiable(legacyIds.toSet()) {
    if (dueDate != null) {
      parseCalendarDate(dueDate!);
    }
    validateTaskDates(dueDate, endDate);
    for (final d in [
      anchorOn,
      scheduleFrom,
      generateFrom,
    ].whereType<String>()) {
      parseCalendarDate(d);
    }
    if (![
      'plant',
      'plants',
      'section',
      'sections',
      'crop',
      'crops',
      'property',
      'manual',
    ].contains(target)) {
      throw ArgumentError('Invalid target');
    }
    if ((target == 'plant' && itemId == null) ||
        (target == 'section' && sectionId == null) ||
        (target == 'crop' && cropId == null)) {
      throw ArgumentError('A specific target is required');
    }
    if (eventType == ActivityType.harvest && eventHarvest == null) {
      throw ArgumentError('Harvest quantity required');
    }
    if (notes.length > 10000) {
      throw ArgumentError('Notes too long');
    }
    if (this.includedTargets.length > 400 ||
        this.excludedTargets.length > 400 ||
        this.legacyIds.length > 400) {
      throw ArgumentError('Use at most 400 explicit targets');
    }
    if ([
      ...this.includedTargets,
      ...this.excludedTargets,
    ].any((k) => !RegExp(r'^[pcs]:.+$').hasMatch(k))) {
      throw ArgumentError('Invalid task target key');
    }
    if (scheduleId != null && (scheduleFrom == null || currentKey == null)) {
      throw ArgumentError(
        'A changed schedule needs its current occurrence identity',
      );
    }
  }
  final String id, propertyId, title, target, notes;
  final String? itemId,
      sectionId,
      cropId,
      taxonId,
      dueDate,
      endDate,
      anchorOn,
      scheduleId,
      scheduleFrom,
      currentKey,
      generateFrom;
  final DateTime createdAt;
  final SectionKind sectionKind;
  final RepeatSchedule repeat;
  final ActivityType? eventType;
  final Harvest? eventHarvest;
  final bool deleted;
  final List<String> includedTargets, excludedTargets, legacyIds;
}

String linkedEventId(String taskId) =>
    const Uuid().v5(Namespace.url.value, 'orchard-atlas/task-event/$taskId');

class TaskOccurrence {
  const TaskOccurrence(this.key, this.startsOn);
  final String key;
  final String? startsOn;
}

List<TaskOccurrence> taskOccurrences(TaskPlan plan, DateTime now) {
  if (plan.deleted) {
    return [];
  }
  final start = parseCalendarDate(
    plan.dueDate ?? calendarDate(plan.createdAt.toLocal()),
  );
  if (plan.repeat == RepeatSchedule.none) {
    return [TaskOccurrence(plan.anchorOn ?? calendarDate(start), plan.dueDate)];
  }
  final today = calendarDate(now), result = <TaskOccurrence>[];
  for (var i = 0; ; i++) {
    final d = calendarDate(switch (plan.repeat) {
      RepeatSchedule.daily => DateTime(start.year, start.month, start.day + i),
      RepeatSchedule.weekly => DateTime(
        start.year,
        start.month,
        start.day + i * 7,
      ),
      RepeatSchedule.monthly => _month(start, i),
      RepeatSchedule.yearly => _month(start, i * 12),
      RepeatSchedule.none => start,
    });
    if (plan.generateFrom != null && d.compareTo(plan.generateFrom!) < 0) {
      continue;
    }
    final key = plan.scheduleId == null
        ? d
        : d == plan.scheduleFrom
        ? plan.currentKey!
        : const Uuid().v5(
            Namespace.url.value,
            '${plan.id}/${plan.scheduleId}/$d',
          );
    if (d.compareTo(today) > 0) {
      if (result.isEmpty) {
        result.add(TaskOccurrence(key, d));
      }
      break;
    }
    result.add(TaskOccurrence(key, d));
    if (d == today) {
      break;
    }
  }
  return result;
}

List<String> occurrenceDates(TaskPlan plan, DateTime now) =>
    taskOccurrences(plan, now).map((o) => o.key).toList();
DateTime _month(DateTime start, int offset) {
  final first = DateTime(start.year, start.month + offset);
  return DateTime(
    first.year,
    first.month,
    math.min(start.day, DateTime(first.year, first.month + 1, 0).day),
  );
}

String taskTargetKey(OrchardTask t) => t.itemId != null
    ? 'p:${t.itemId}'
    : t.cropId != null
    ? 'c:${t.cropId}'
    : t.sectionId != null
    ? 's:${t.sectionId}'
    : 'property';
bool belongsToTaskPlan(OrchardTask t, TaskPlan p) =>
    t.propertyId == p.propertyId &&
    (t.planId == p.id || t.groupId == p.id || p.legacyIds.contains(t.id));

/// Indexes parent and legacy links once for large task collections.
class TaskPlanLookup {
  TaskPlanLookup(List<TaskPlan> plans) {
    for (final p in plans) {
      _definitions['${p.propertyId}/${p.id}'] = p;
      for (final id in p.legacyIds) {
        _legacy['${p.propertyId}/$id'] = p;
      }
    }
  }
  final _definitions = <String, TaskPlan>{};
  final _legacy = <String, TaskPlan>{};
  TaskPlan? forTask(OrchardTask t) =>
      _definitions['${t.propertyId}/${t.planId}'] ??
      _definitions['${t.propertyId}/${t.groupId}'] ??
      _legacy['${t.propertyId}/${t.id}'];
}

TaskPlan? planForTask(OrchardTask task, List<TaskPlan> plans) =>
    plans.where((p) => belongsToTaskPlan(task, p)).firstOrNull;
String taskCycleKey(OrchardTask t, TaskPlan p) =>
    t.occurrenceOn ??
    p.anchorOn ??
    t.dueDate ??
    calendarDate(t.createdAt.toLocal());
bool visibleTask(OrchardTask t, List<TaskPlan> plans) =>
    !t.membershipExcluded &&
    t.status != TaskStatus.deleted &&
    !(planForTask(t, plans)?.deleted ?? false);

Set<String> matchingTaskTargets(
  TaskPlan plan, {
  required List<ManagedPlant> plants,
  required List<OrchardSection> sections,
  required List<CropPlanting> crops,
  required Taxonomy taxonomy,
  bool overrides = true,
}) {
  if (plan.deleted) {
    return {};
  }
  final taxa = plan.taxonId == null
      ? null
      : taxonomy.descendants(plan.taxonId!);
  final scope = plan.sectionId == null
      ? null
      : sectionDescendants(plan.sectionId!, sections);
  final activePlants = plants.where(
    (p) => p.propertyId == plan.propertyId && p.status == ItemStatus.active,
  );
  final activeCrops = crops.where(
    (c) => c.propertyId == plan.propertyId && c.status == CropStatus.growing,
  );
  final activeSections = sections.where((s) => s.propertyId == plan.propertyId);
  final valid = {
    for (final p in activePlants) 'p:${p.id}',
    for (final c in activeCrops) 'c:${c.id}',
    for (final s in activeSections) 's:${s.id}',
    'property',
  };
  final keys = <String>{};
  if (plan.target == 'plant') {
    keys.add('p:${plan.itemId}');
  }
  if (plan.target == 'crop') {
    keys.add('c:${plan.cropId}');
  }
  if (plan.target == 'section') {
    keys.add('s:${plan.sectionId}');
  }
  if (plan.target == 'property') {
    keys.add('property');
  }
  if (plan.target == 'plants' || plan.target == 'crops') {
    if (plan.target == 'plants') {
      keys.addAll(
        activePlants
            .where(
              (p) =>
                  (taxa == null || taxa.contains(p.taxonId)) &&
                  (scope == null || scope.contains(p.sectionId)),
            )
            .map((p) => 'p:${p.id}'),
      );
    }
    keys.addAll(
      activeCrops
          .where(
            (c) =>
                (taxa == null || taxa.contains(c.taxonId)) &&
                (scope == null || scope.contains(c.sectionId)),
          )
          .map((c) => 'c:${c.id}'),
    );
  }
  if (plan.target == 'sections') {
    keys.addAll(
      activeSections
          .where(
            (s) =>
                s.kind == plan.sectionKind &&
                (scope == null || scope.contains(s.id)),
          )
          .map((s) => 's:${s.id}'),
    );
  }
  if (overrides) {
    keys.addAll(plan.includedTargets);
    keys.removeAll(plan.excludedTargets);
  }
  return keys.intersection(valid);
}

OrchardTask taskWithMembership(OrchardTask t, bool excluded) => OrchardTask(
  id: t.id,
  propertyId: t.propertyId,
  title: t.title,
  notes: t.notes,
  createdAt: t.createdAt,
  itemId: t.itemId,
  sectionId: t.sectionId,
  cropId: t.cropId,
  groupId: t.groupId,
  groupScope: t.groupScope,
  dueDate: t.dueDate,
  endDate: t.endDate,
  completedOn: t.completedOn,
  planId: t.planId,
  occurrenceOn: t.occurrenceOn,
  eventType: t.eventType,
  eventHarvest: t.eventHarvest,
  status: t.status,
  membershipExcluded: excluded,
);
bool alreadyRecordedTarget(
  Iterable<OrchardTask> members,
  String key,
  String? date,
) =>
    date != null &&
    members.any(
      (t) =>
          taskTargetKey(t) == key &&
          t.dueDate == date &&
          t.status != TaskStatus.open &&
          t.status != TaskStatus.deleted,
    );

List<OrchardTask> expandPlans({
  required List<TaskPlan> plans,
  required List<OrchardTask> existing,
  required List<ManagedPlant> plants,
  required List<OrchardSection> sections,
  required List<CropPlanting> crops,
  required Taxonomy taxonomy,
  required DateTime now,
}) {
  final result = <OrchardTask>[], known = existing.map((t) => t.id).toSet();
  for (final plan in plans.where((p) => !p.deleted)) {
    final keys = matchingTaskTargets(
      plan,
      plants: plants,
      sections: sections,
      crops: crops,
      taxonomy: taxonomy,
    );
    final occurrences = taskOccurrences(plan, now),
        current = occurrences.last.key;
    final members = existing.where((t) => belongsToTaskPlan(t, plan)).toList();
    final membersByCycle = <String, Set<String>>{};
    final recordedByDate = <String, Set<String>>{};
    for (final t in members) {
      membersByCycle
          .putIfAbsent(taskCycleKey(t, plan), () => {})
          .add(taskTargetKey(t));
      if (t.dueDate != null &&
          t.status != TaskStatus.open &&
          t.status != TaskStatus.deleted) {
        recordedByDate.putIfAbsent(t.dueDate!, () => {}).add(taskTargetKey(t));
      }
    }
    for (final occurrence in occurrences) {
      if (occurrence.key != current &&
          membersByCycle.containsKey(occurrence.key)) {
        continue;
      }
      for (final key in keys) {
        if (recordedByDate[occurrence.startsOn]?.contains(key) ?? false) {
          continue;
        }
        if (membersByCycle[occurrence.key]?.contains(key) ?? false) {
          continue;
        }
        final kind = key == 'property' ? 'property' : key.substring(0, 1),
            targetId = key == 'property' ? null : key.substring(2);
        final oldTargetKey =
            kind == 'c' && !['crop', 'crops'].contains(plan.target)
            ? 'crop:$targetId'
            : targetId ?? 'property';
        final id = const Uuid().v5(
          Namespace.url.value,
          '${plan.id}/${occurrence.key}/$oldTargetKey',
        );
        if (!known.add(id)) {
          continue;
        }
        result.add(
          OrchardTask(
            id: id,
            propertyId: plan.propertyId,
            title: plan.title,
            createdAt: plan.createdAt,
            itemId: kind == 'p' ? targetId : null,
            sectionId: kind == 's' ? targetId : null,
            cropId: kind == 'c' ? targetId : null,
            groupId: key == 'property' ? null : plan.id,
            groupScope: plan.target,
            planId: plan.id,
            occurrenceOn: occurrence.key,
            dueDate: occurrence.startsOn,
            endDate: plan.endDate == null
                ? null
                : plan.repeat == RepeatSchedule.none
                ? plan.endDate
                : offsetCalendarDate(
                    occurrence.startsOn!,
                    taskRangeDays(plan.dueDate!, plan.endDate!),
                  ),
            eventType: kind == 'p' ? plan.eventType : null,
            eventHarvest: plan.eventHarvest,
            notes: plan.notes,
          ),
        );
      }
    }
  }
  return result;
}

int compareTasks(OrchardTask a, OrchardTask b, TaskSort sort, DateTime now) {
  if (sort == TaskSort.newest) return b.createdAt.compareTo(a.createdAt);
  if (sort == TaskSort.oldest) return a.createdAt.compareTo(b.createdAt);
  if (sort == TaskSort.title) {
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
  if (sort == TaskSort.status) return a.status.index.compareTo(b.status.index);
  if (a.dueDate == null || b.dueDate == null) {
    return a.dueDate == b.dueDate
        ? a.title.compareTo(b.title)
        : a.dueDate == null
        ? -1
        : 1;
  }
  final today = calendarDate(now),
      aOverdue = (a.endDate ?? a.dueDate!).compareTo(today) < 0,
      bOverdue = (b.endDate ?? b.dueDate!).compareTo(today) < 0;
  if (aOverdue != bOverdue) return aOverdue ? 1 : -1;
  return a.dueDate!.compareTo(b.dueDate!);
}

Coordinates sectionCenter(OrchardSection s) {
  if (s.kind == SectionKind.row) {
    final points = s.vertices;
    final lengths = [
      for (var i = 1; i < points.length; i++)
        _distance(points[i - 1], points[i]),
    ];
    var halfway = lengths.fold(0.0, (a, b) => a + b) / 2;
    for (var i = 0; i < lengths.length; i++) {
      if (halfway <= lengths[i]) {
        final f = lengths[i] == 0 ? 0.0 : halfway / lengths[i];
        return Coordinates(
          points[i].latitude +
              (points[i + 1].latitude - points[i].latitude) * f,
          points[i].longitude +
              (points[i + 1].longitude - points[i].longitude) * f,
        );
      }
      halfway -= lengths[i];
    }
  }
  return Coordinates(
    s.vertices.map((p) => p.latitude).reduce((a, b) => a + b) /
        s.vertices.length,
    s.vertices.map((p) => p.longitude).reduce((a, b) => a + b) /
        s.vertices.length,
  );
}

double _distance(Coordinates a, Coordinates b) => math.sqrt(
  math.pow(a.latitude - b.latitude, 2) +
      math.pow(
        (a.longitude - b.longitude) * math.cos(a.latitude * math.pi / 180),
        2,
      ),
);
double rowPosition(ManagedPlant plant, OrchardSection row) {
  if (plant.rowOrder != null) return plant.rowOrder!;
  var station = 0.0, best = double.infinity, bestStation = 0.0, total = 0.0;
  for (var i = 1; i < row.vertices.length; i++) {
    total += _distance(row.vertices[i - 1], row.vertices[i]);
  }
  for (var i = 1; i < row.vertices.length; i++) {
    final a = row.vertices[i - 1], b = row.vertices[i];
    final dx = b.longitude - a.longitude, dy = b.latitude - a.latitude;
    final denominator = dx * dx + dy * dy;
    final f = denominator == 0
        ? 0.0
        : ((plant.location.longitude - a.longitude) * dx +
                  (plant.location.latitude - a.latitude) * dy) /
              denominator;
    final t = f.clamp(0.0, 1.0), length = _distance(a, b);
    final distance = _distance(
      plant.location,
      Coordinates(a.latitude + dy * t, a.longitude + dx * t),
    );
    if (distance < best) {
      best = distance;
      bestStation = station + length * t;
    }
    station += length;
  }
  return total == 0 ? 0 : bestStation / total;
}

List<ManagedPlant> orderedRowPlants(
  OrchardSection row,
  Iterable<ManagedPlant> plants,
) => plants.where((p) => p.sectionId == row.id).toList()
  ..sort((a, b) {
    final order = rowPosition(a, row).compareTo(rowPosition(b, row));
    return order == 0 ? a.createdAt.compareTo(b.createdAt) : order;
  });

/// Calendar/reminder projection normalizes legacy links without rewriting facts.
List<OrchardTask> projectedTaskEntries({
  required List<TaskPlan> plans,
  required List<OrchardTask> tasks,
  required List<ManagedPlant> plants,
  required List<OrchardSection> sections,
  required List<CropPlanting> crops,
  required Taxonomy taxonomy,
  required DateTime through,
}) {
  final predicted = expandPlans(
    plans: plans,
    existing: tasks,
    plants: plants,
    sections: sections,
    crops: crops,
    taxonomy: taxonomy,
    now: through,
  );
  final raw = [...tasks, ...predicted];
  final lookup = TaskPlanLookup(plans);
  final occurrences = <String, Map<String, TaskOccurrence>>{
    for (final p in plans.where((p) => !p.deleted))
      p.id: {for (final o in taskOccurrences(p, through)) o.key: o},
  };
  final representedCycles = <String>{};
  final result = <OrchardTask>[];
  for (final t in raw) {
    final p = lookup.forTask(t);
    if (p != null) {
      representedCycles.add('${p.id}/${taskCycleKey(t, p)}');
    }
    if (t.membershipExcluded ||
        t.status == TaskStatus.deleted ||
        (p?.deleted ?? false)) {
      continue;
    }
    if (p == null) {
      result.add(t);
      continue;
    }
    final key = taskCycleKey(t, p);
    final occurrence = occurrences[p.id]?[key];
    final start = occurrence?.startsOn ?? t.dueDate;
    final end = occurrence == null
        ? t.endDate
        : p.endDate == null
        ? null
        : p.repeat == RepeatSchedule.none
        ? p.endDate
        : offsetCalendarDate(start!, taskRangeDays(p.dueDate!, p.endDate!));
    final title = occurrence == null ? t.title : p.title;
    final notes = occurrence == null ? t.notes : p.notes;
    if (t.planId == p.id &&
        t.occurrenceOn == key &&
        t.dueDate == start &&
        t.endDate == end &&
        t.title == title &&
        t.notes == notes) {
      result.add(t);
    } else {
      result.add(
        OrchardTask(
          id: t.id,
          propertyId: t.propertyId,
          title: title,
          notes: notes,
          createdAt: t.createdAt,
          itemId: t.itemId,
          sectionId: t.sectionId,
          cropId: t.cropId,
          groupId: t.groupId,
          groupScope: t.groupScope,
          dueDate: start,
          endDate: end,
          completedOn: t.completedOn,
          planId: p.id,
          occurrenceOn: key,
          eventType: t.eventType,
          eventHarvest: t.eventHarvest,
          status: t.status,
        ),
      );
    }
  }
  for (final p in plans.where((p) => !p.deleted)) {
    for (final o in occurrences[p.id]!.values) {
      if (representedCycles.contains('${p.id}/${o.key}')) {
        continue;
      }
      result.add(
        OrchardTask(
          id: '${p.id}/${o.key}',
          propertyId: p.propertyId,
          title: p.title,
          notes: p.notes,
          createdAt: p.createdAt,
          planId: p.id,
          occurrenceOn: o.key,
          dueDate: o.startsOn,
          endDate: p.endDate == null
              ? null
              : p.repeat == RepeatSchedule.none
              ? p.endDate
              : offsetCalendarDate(
                  o.startsOn!,
                  taskRangeDays(p.dueDate!, p.endDate!),
                ),
        ),
      );
    }
  }
  return result;
}
