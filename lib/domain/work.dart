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
    this.repeat = RepeatSchedule.none,
    this.eventType,
    this.eventHarvest,
    this.notes = '',
  }) : title = requiredText(title, 'Task title') {
    if (dueDate != null) parseCalendarDate(dueDate!);
    if (![
      'plant',
      'section',
      'crop',
      'plants',
      'sections',
      'crops',
      'property',
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
    if (notes.length > 10000) throw ArgumentError('Notes too long');
  }
  final String id, propertyId, title, target, notes;
  final String? itemId, sectionId, cropId, taxonId, dueDate;
  final DateTime createdAt;
  final SectionKind sectionKind;
  final RepeatSchedule repeat;
  final ActivityType? eventType;
  final Harvest? eventHarvest;
}

String linkedEventId(String taskId) =>
    const Uuid().v5(Namespace.url.value, 'orchard-atlas/task-event/$taskId');

List<String> occurrenceDates(TaskPlan plan, DateTime now) {
  final start = parseCalendarDate(
    plan.dueDate ?? calendarDate(plan.createdAt.toLocal()),
  );
  final today = parseCalendarDate(calendarDate(now));
  if (plan.repeat == RepeatSchedule.none) return [calendarDate(start)];
  final result = <String>[];
  for (var i = 0; ; i++) {
    final date = switch (plan.repeat) {
      RepeatSchedule.daily => DateTime(start.year, start.month, start.day + i),
      RepeatSchedule.weekly => DateTime(
        start.year,
        start.month,
        start.day + i * 7,
      ),
      RepeatSchedule.monthly => _month(start, i),
      RepeatSchedule.yearly => _month(start, i * 12),
      RepeatSchedule.none => start,
    };
    if (date.isAfter(today)) {
      if (result.isEmpty) result.add(calendarDate(date));
      break;
    }
    result.add(calendarDate(date));
    if (date.isAtSameMomentAs(today)) break;
  }
  return result;
}

DateTime _month(DateTime start, int offset) {
  final first = DateTime(start.year, start.month + offset);
  return DateTime(
    first.year,
    first.month,
    math.min(start.day, DateTime(first.year, first.month + 1, 0).day),
  );
}

List<OrchardTask> expandPlans({
  required List<TaskPlan> plans,
  required List<OrchardTask> existing,
  required List<ManagedPlant> plants,
  required List<OrchardSection> sections,
  required List<CropPlanting> crops,
  required Taxonomy taxonomy,
  required DateTime now,
}) {
  final known = existing.map((t) => t.id).toSet(), result = <OrchardTask>[];
  for (final plan in plans) {
    final taxa = plan.taxonId == null
        ? null
        : taxonomy.descendants(plan.taxonId!);
    final scope = plan.sectionId == null
        ? null
        : sectionDescendants(plan.sectionId!, sections);
    final targets = <({String? plant, String? section, String? crop})>[];
    if (plan.target == 'plant') {
      if (plants.any(
        (p) =>
            p.propertyId == plan.propertyId &&
            p.id == plan.itemId &&
            p.status == ItemStatus.active,
      )) {
        targets.add((plant: plan.itemId, section: null, crop: null));
      }
    } else if (plan.target == 'plants') {
      for (final p in plants.where(
        (p) =>
            p.propertyId == plan.propertyId &&
            p.status == ItemStatus.active &&
            (taxa == null || taxa.contains(p.taxonId)) &&
            (scope == null || scope.contains(p.sectionId)),
      )) {
        targets.add((plant: p.id, section: null, crop: null));
      }
    } else if (plan.target == 'sections') {
      for (final s in sections.where(
        (s) =>
            s.propertyId == plan.propertyId &&
            s.kind == plan.sectionKind &&
            (scope == null || scope.contains(s.id)),
      )) {
        targets.add((plant: null, section: s.id, crop: null));
      }
    } else if (plan.target == 'crops') {
      for (final c in crops.where(
        (c) =>
            c.propertyId == plan.propertyId &&
            c.status == CropStatus.growing &&
            (taxa == null || taxa.contains(c.taxonId)) &&
            (scope == null || scope.contains(c.sectionId)),
      )) {
        targets.add((plant: null, section: null, crop: c.id));
      }
    } else if (plan.target == 'section') {
      if (sections.any(
        (s) => s.propertyId == plan.propertyId && s.id == plan.sectionId,
      )) {
        targets.add((plant: null, section: plan.sectionId, crop: null));
      }
    } else if (plan.target == 'crop') {
      if (crops.any(
        (c) => c.propertyId == plan.propertyId && c.id == plan.cropId,
      )) {
        targets.add((plant: null, section: null, crop: plan.cropId));
      }
    } else {
      targets.add((plant: null, section: null, crop: null));
    }
    final dates = occurrenceDates(plan, now);
    final current = dates.last;
    for (final date in dates) {
      for (final target in targets) {
        // New matches join the current occurrence; historic completed membership stays intact.
        if (date != current &&
            existing.any(
              (t) => t.planId == plan.id && t.occurrenceOn == date,
            )) {
          continue;
        }
        final id = const Uuid().v5(
          Namespace.url.value,
          '${plan.id}/$date/${target.plant ?? target.section ?? target.crop ?? 'property'}',
        );
        if (!known.add(id)) continue;
        result.add(
          OrchardTask(
            id: id,
            propertyId: plan.propertyId,
            title: plan.title,
            createdAt: plan.createdAt,
            itemId: target.plant,
            sectionId: target.section,
            cropId: target.crop,
            groupId:
                target.plant == null &&
                    target.section == null &&
                    target.crop == null
                ? null
                : plan.id,
            groupScope: plan.target,
            planId: plan.id,
            occurrenceOn: date,
            dueDate: plan.dueDate == null && plan.repeat == RepeatSchedule.none
                ? null
                : date,
            eventType: target.plant == null ? null : plan.eventType,
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
      aOverdue = a.dueDate!.compareTo(today) < 0,
      bOverdue = b.dueDate!.compareTo(today) < 0;
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
