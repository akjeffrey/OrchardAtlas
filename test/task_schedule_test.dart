import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/task_calendar.dart';
import 'package:orchard_atlas/domain/task_edits.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/data/work_mapping.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/application/extensions.dart';

OrchardTask task({
  String id = 'task',
  String? end = '2027-03-30',
  TaskStatus status = TaskStatus.open,
}) => OrchardTask(
  id: id,
  propertyId: 'orchard',
  title: 'Prune',
  createdAt: DateTime.utc(2027),
  dueDate: '2027-03-28',
  endDate: end,
  status: status,
);
void main() {
  test('date ranges reject missing starts and reversed dates', () {
    expect(() => task(end: '2027-03-27'), throwsArgumentError);
    expect(() => validateTaskDates(null, '2027-03-28'), throwsArgumentError);
    expect(task(end: null).endDate, isNull);
    expect(task().withStatus(TaskStatus.completed).endDate, '2027-03-30');
  });
  test('legacy and multiple reminder offsets are bounded and deduplicated', () {
    expect(reminderOffsets({'days': 7}), [7]);
    expect(
      reminderOffsets({
        'offsets': [0, 7, 7, 14, -1, 366, 'bad'],
      }),
      [0, 7, 14],
    );
  });
  test(
    'each offset creates a distinct reminder, completed and past are skipped',
    () {
      final rows = dueNotifications(
        [task(), task(id: 'done', status: TaskStatus.completed)],
        [
          {
            'id': 'task',
            'offsets': [0, 7, 14],
          },
        ],
        DateTime(2027, 3, 20),
      );
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['id']).toSet(), hasLength(2));
      expect(
        rows.map(
          (r) => DateTime.fromMillisecondsSinceEpoch(r['time'] as int).day,
        ),
        [21, 28],
      );
    },
  );
  test(
    'calendar range has UTC exclusive end, undated and cancelled are skipped',
    () {
      final rows = taskCalendarEvents([
        task(),
        task(id: 'cancel', status: TaskStatus.cancelled),
      ]);
      expect(rows, hasLength(1));
      expect(
        rows.single['start'],
        DateTime.utc(2027, 3, 28).millisecondsSinceEpoch,
      );
      expect(
        rows.single['end'],
        DateTime.utc(2027, 3, 31).millisecondsSinceEpoch,
      );
      expect(
        taskCalendarEvents([task(end: null)]).single['end'],
        DateTime.utc(2027, 3, 29).millisecondsSinceEpoch,
      );
    },
  );
  test(
    'group calendar event aggregates completion and stable occurrence identity',
    () {
      OrchardTask member(String id, TaskStatus status) => OrchardTask(
        id: id,
        propertyId: 'orchard',
        title: 'Prune',
        createdAt: DateTime.utc(2027),
        dueDate: '2027-03-28',
        planId: 'plan',
        occurrenceOn: '2027-03-28',
        status: status,
      );
      final rows = taskCalendarEvents([
        member('a', TaskStatus.open),
        member('b', TaskStatus.completed),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'plan/2027-03-28');
      expect(rows.single['description'], contains('1/2 complete'));
    },
  );
  test(
    'task and plan mappings retain ranges and old documents remain readable',
    () {
      final t = task();
      final map = FirestoreMapping.taskToMap(t);
      expect(
        FirestoreMapping.taskFromMap('orchard', 'task', map).endDate,
        t.endDate,
      );
      map.remove('endDate');
      expect(
        FirestoreMapping.taskFromMap('orchard', 'task', map).endDate,
        isNull,
      );
      final p = TaskPlan(
        id: 'p',
        propertyId: 'orchard',
        title: 'Prune',
        createdAt: DateTime.utc(2027),
        target: 'property',
        dueDate: '2027-03-28',
        endDate: '2027-03-30',
        repeat: RepeatSchedule.weekly,
      );
      expect(
        WorkMapping.readPlan('orchard', 'p', WorkMapping.plan(p)).endDate,
        p.endDate,
      );
      final expanded = expandPlans(
        plans: [p],
        existing: [],
        plants: [],
        sections: [],
        crops: [],
        taxonomy: Taxonomy([]),
        now: DateTime(2027, 4, 4),
      );
      expect(expanded.last.dueDate, '2027-04-04');
      expect(expanded.last.endDate, '2027-04-06');
      expect(
        editOpenTask(
          t,
          title: 'Updated',
          notes: '',
          dueDate: t.dueDate,
          endDate: t.endDate,
        ).endDate,
        t.endDate,
      );
    },
  );
}
