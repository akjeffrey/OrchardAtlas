import 'models.dart';

abstract interface class TaskCalendarRepository {
  Future<List<Map<String, dynamic>>> calendars();
  Future<String?> selected(String scope);
  Future<void> select(String scope, String? calendar);
  Future<void> replace(String scope, List<Map<String, dynamic>> events);
}

/// One all-day calendar event per task/plan occurrence, not per matching plant.
/// End dates are inclusive in OrchardAtlas; calendar providers use exclusive ends.
List<Map<String, dynamic>> taskCalendarEvents(List<OrchardTask> tasks) {
  final groups = <String, List<OrchardTask>>{};
  for (final t in tasks) {
    if (t.dueDate == null ||
        t.status == TaskStatus.cancelled ||
        t.status == TaskStatus.skipped ||
        t.status == TaskStatus.deleted) {
      continue;
    }
    final key = t.planId != null
        ? '${t.planId}/${t.occurrenceOn ?? t.dueDate}'
        : t.groupId != null
        ? 'group/${t.groupId}/${t.dueDate}'
        : t.id;
    groups.putIfAbsent(key, () => []).add(t);
  }
  final entries = <Map<String, dynamic>>[];
  for (final e in groups.entries) {
    final t = e.value.first;
    final start = parseCalendarDate(t.dueDate!);
    final last = parseCalendarDate(t.endDate ?? t.dueDate!);
    final completed = e.value
        .where((t) => t.status == TaskStatus.completed)
        .length;
    entries.add({
      'id': e.key,
      'title': '${completed == e.value.length ? '✓ ' : ''}${t.title}',
      'description':
          'OrchardAtlas · $completed/${e.value.length} complete\n${t.notes}',
      'start': DateTime.utc(
        start.year,
        start.month,
        start.day,
      ).millisecondsSinceEpoch,
      'end': DateTime.utc(
        last.year,
        last.month,
        last.day + 1,
      ).millisecondsSinceEpoch,
    });
  }
  entries.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
  return entries;
}
