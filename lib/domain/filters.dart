import 'models.dart';
import 'taxonomy.dart';

class PlantFilter {
  const PlantFilter({
    this.query = '',
    this.taxonId,
    this.year,
    this.status = ItemStatus.active,
  });
  final String query;
  final String? taxonId;
  final int? year;
  final ItemStatus? status;
  List<ManagedPlant> apply(Iterable<ManagedPlant> plants, Taxonomy taxonomy) {
    final ids = taxonId == null ? null : taxonomy.descendants(taxonId!);
    final search = query.trim().toLowerCase();
    return plants.where((p) {
      final labels = taxonomy.taxa.any((t) => t.id == p.taxonId)
          ? taxonomy.ancestry(p.taxonId).map((t) => t.name).join(' ')
          : '';
      return (status == null || p.status == status) &&
          (ids == null || ids.contains(p.taxonId)) &&
          (year == null ||
              (p.plantedOn != null &&
                  parseCalendarDate(p.plantedOn!).year == year)) &&
          '$labels ${p.name} ${p.rootstock} ${p.nursery} ${p.notes}'
              .toLowerCase()
              .contains(search);
    }).toList();
  }
}

enum TaskWindow { all, today, thisWeek, upcoming }

bool taskInWindow(OrchardTask task, TaskWindow window, DateTime now) {
  if (window == TaskWindow.all) return true;
  if (task.dueDate == null) return window == TaskWindow.upcoming;
  final due = parseCalendarDate(task.dueDate!);
  final today = DateTime(now.year, now.month, now.day);
  final weekEnd = today.add(Duration(days: 7 - today.weekday));
  return switch (window) {
    TaskWindow.all => true,
    TaskWindow.today => !due.isAfter(today), // Include overdue work.
    TaskWindow.thisWeek => !due.isAfter(weekEnd),
    TaskWindow.upcoming => due.isAfter(weekEnd),
  };
}
