import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/application/extensions.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/domain/task_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'deleting an occurrence remains offline and does not stop future repeats',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalTrialRepository.open(prefs);
      final plan = TaskPlan(
        id: 'plan',
        propertyId: repo.place.id,
        title: 'Prune',
        createdAt: DateTime(2027),
        target: 'property',
        dueDate: '2027-01-01',
        repeat: RepeatSchedule.weekly,
      );
      repo.saveTaskPlan(plan);
      final task = expandPlans(
        plans: [plan],
        existing: [],
        plants: [],
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        now: DateTime(2027),
      ).single;
      repo.saveTask(task);
      OrchardCommands(
        repo,
        starterTaxonomy,
      ).changeTaskStatus(task, TaskStatus.deleted, repo.place.ownerId);
      await repo.flushForBackup();
      final reopened = LocalTrialRepository.open(prefs);
      final saved = (await reopened.watchTasks(repo.place.id).first).value;
      expect(saved.single.status, TaskStatus.deleted);
      final future = expandPlans(
        plans: [plan],
        existing: saved,
        plants: [],
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        now: DateTime(2027, 1, 8),
      );
      expect(future, hasLength(1));
      expect(future.single.dueDate, '2027-01-08');
      expect(taskCalendarEvents(saved), isEmpty);
      expect(
        dueNotifications(saved, [
          {
            'id': 'plan',
            'offsets': [0],
          },
        ], DateTime(2026)),
        isEmpty,
      );
      final map = FirestoreMapping.taskToMap(saved.single);
      expect(
        FirestoreMapping.taskFromMap(repo.place.id, task.id, map).status,
        TaskStatus.deleted,
      );
    },
  );
  test('completion, skip and reopen preserve activity behavior', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalTrialRepository.open(
      await SharedPreferences.getInstance(),
    );
    final commands = OrchardCommands(repo, starterTaxonomy);
    final plant = commands.addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: starterTaxonomy.taxa[2].id,
      location: Coordinates(1, 2),
    );
    final task = OrchardTask(
      id: 'task',
      propertyId: repo.place.id,
      title: 'Prune',
      createdAt: DateTime(2027),
      itemId: plant.id,
      eventType: ActivityType.pruning,
    );
    repo.saveTask(task);
    commands.changeTaskStatus(task, TaskStatus.completed, repo.place.ownerId);
    expect(repo.events.single.type, ActivityType.pruning);
    commands.changeTaskStatus(
      repo.tasks.single,
      TaskStatus.skipped,
      repo.place.ownerId,
    );
    expect(repo.events, isEmpty);
    commands.changeTaskStatus(
      repo.tasks.single,
      TaskStatus.open,
      repo.place.ownerId,
    );
    commands.changeTaskStatus(
      repo.tasks.single,
      TaskStatus.completed,
      repo.place.ownerId,
    );
    expect(repo.events, hasLength(1));
    commands.changeTaskStatus(
      repo.tasks.single,
      TaskStatus.deleted,
      repo.place.ownerId,
    );
    expect(repo.events, isEmpty);
  });
}
