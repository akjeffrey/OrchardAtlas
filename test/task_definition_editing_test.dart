import 'package:orchard_atlas/application/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/domain/task_edits.dart';
import 'package:orchard_atlas/domain/task_definition_changes.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/domain/task_calendar.dart';
import 'package:orchard_atlas/data/work_mapping.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 27);
  final apple = starterTaxonomy.taxa
          .firstWhere((t) => t.name == 'Domestic apple')
          .id,
      pear = starterTaxonomy.taxa
          .firstWhere((t) => t.name == 'European pear')
          .id;
  ManagedPlant plant(String id, {String? taxon, String property = 'p'}) =>
      ManagedPlant(
        id: id,
        propertyId: property,
        name: id,
        taxonId: taxon ?? apple,
        location: Coordinates(1, 2),
        createdAt: now,
      );
  List<OrchardTask> expand(
    TaskPlan plan,
    List<OrchardTask> existing,
    List<ManagedPlant> plants, {
    DateTime? at,
  }) => expandPlans(
    plans: [plan],
    existing: existing,
    plants: plants,
    sections: [],
    crops: [],
    taxonomy: starterTaxonomy,
    now: at ?? now,
  );
  List<OrchardTask> changes(
    TaskPlan old,
    TaskPlan edited,
    List<OrchardTask> existing,
    List<ManagedPlant> plants,
  ) => taskDefinitionChanges(
    old: old,
    edited: edited,
    existing: existing,
    plants: plants,
    sections: [],
    crops: [],
    taxonomy: starterTaxonomy,
    now: now,
  );
  List<OrchardTask> apply(List<OrchardTask> old, List<OrchardTask> changes) => {
    for (final t in old) t.id: t,
    for (final t in changes) t.id: t,
  }.values.toList();
  TaskPlan plan({
    String target = 'plants',
    String? type,
    String due = '2026-11-27',
    RepeatSchedule repeat = RepeatSchedule.weekly,
  }) => TaskPlan(
    id: 'plan',
    propertyId: 'p',
    title: 'Prune',
    createdAt: now,
    target: target,
    taxonId: type,
    dueDate: due,
    repeat: repeat,
    eventType: ActivityType.pruning,
  );
  test('reanchor keeps current completion identities and dates while changing open and future work', () {
    final p = plan(), plants = [plant('a'), plant('b')];
    final original = expand(p, [], plants);
    final existing = [
      original.first.withStatus(TaskStatus.completed, now: now),
      original.last,
    ];
    final edited = editPlan(
      p,
      title: p.title,
      notes: '',
      dueDate: '2027-02-01',
      endDate: '2027-02-03',
      eventType: p.eventType,
      now: now,
    );
    final updated = apply(existing, changes(p, edited, existing, plants));
    expect(updated.first.status, TaskStatus.completed);
    expect(updated.first.dueDate, '2026-11-27');
    expect(updated.last.id, original.last.id);
    expect(updated.last.dueDate, '2027-02-01');
    expect(updated.last.endDate, '2027-02-03');
    expect(
      taskOccurrences(edited, now).single.key,
      original.first.occurrenceOn,
    );
    expect(expand(edited, updated, plants), isEmpty);
    final future = expand(edited, updated, plants, at: DateTime(2027, 2, 8));
    expect(future, hasLength(2));
    expect(future.map((t) => t.id).toSet(), hasLength(2));
    expect(future.every((t) => t.dueDate == '2027-02-08'), isTrue);
    final projection = projectedTaskEntries(
      plans: [edited],
      tasks: updated,
      plants: plants,
      sections: [],
      crops: [],
      taxonomy: starterTaxonomy,
      through: now,
    );
    expect(
      taskCalendarEvents(projection).single['description'],
      contains('1/2 complete'),
    );
  });
  test('reanchoring from a future year back to the present has no date/key collisions', () {
    final p = plan(due: '2027-06-06'), plants = [plant('a')];
    final existing = expand(p, [], plants);
    final edited = editPlan(
      p,
      title: p.title,
      notes: '',
      dueDate: '2026-11-01',
      now: now,
    );
    final updated = apply(existing, changes(p, edited, existing, plants));
    final future = expand(edited, updated, plants, at: DateTime(2027, 6, 8));
    final all = [...updated, ...future];
    expect(all.map((t) => t.id).toSet(), hasLength(all.length));
    expect(all.map((t) => t.occurrenceOn).toSet(), hasLength(all.length));
    expect(all.any((t) => t.dueDate == '2027-06-06'), isTrue);
    expect(taskOccurrences(edited, now).length, 1);
  });
  test('criteria edits, individual outliers and exclusions apply to current and newly matching plants', () {
    final p = plan(type: apple),
        plants = [plant('a'), plant('done'), plant('pear', taxon: pear)];
    final original = expand(p, [], plants);
    final existing = [
      original.first,
      original.last.withStatus(TaskStatus.completed, now: now),
    ];
    final edited = editPlan(
      p,
      title: p.title,
      notes: '',
      dueDate: p.dueDate,
      target: 'plants',
      taxonId: pear,
      updateTargets: true,
      includedTargets: ['p:a'],
      excludedTargets: ['p:pear'],
      now: now,
    );
    var updated = apply(existing, changes(p, edited, existing, plants));
    expect(updated.first.membershipExcluded, isFalse);
    expect(updated.last.status, TaskStatus.completed);
    final newcomers = [
      ...plants,
      plant('new pear', taxon: pear),
      plant('new apple'),
    ];
    expect(expand(edited, updated, newcomers).map((t) => t.itemId), [
      'new pear',
    ]);
    final removed = editPlan(
      edited,
      title: p.title,
      notes: '',
      dueDate: p.dueDate,
      target: 'plants',
      taxonId: pear,
      updateTargets: true,
      includedTargets: [],
      excludedTargets: ['p:a', 'p:pear'],
      now: now,
    );
    updated = apply(updated, changes(edited, removed, updated, plants));
    expect(updated.first.membershipExcluded, isTrue);
    final restored = editPlan(
      removed,
      title: p.title,
      notes: '',
      dueDate: p.dueDate,
      target: 'plants',
      taxonId: pear,
      updateTargets: true,
      includedTargets: ['p:a'],
      excludedTargets: ['p:pear'],
      now: now,
    );
    updated = apply(updated, changes(removed, restored, updated, plants));
    expect(updated.first.id, existing.first.id);
    expect(updated.first.membershipExcluded, isFalse);
    expect(expand(restored, updated, plants), isEmpty);
  });
  test('deleting definitions stops all future expansion and exports but retains completed facts', () {
    final p = plan(), plants = [plant('a'), plant('b')];
    final original = expand(p, [], plants);
    final existing = [
      original.first.withStatus(TaskStatus.completed, now: now),
      original.last,
    ];
    final deleted = deletedTaskPlan(p),
        updated = apply(existing, changes(p, deleted, existing, plants));
    expect(updated.first.status, TaskStatus.completed);
    expect(updated.last.status, TaskStatus.deleted);
    expect(expand(deleted, updated, plants, at: DateTime(2030)), isEmpty);
    expect(
      projectedTaskEntries(
        plans: [deleted],
        tasks: updated,
        plants: plants,
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        through: DateTime(2030),
      ),
      isEmpty,
    );
    expect(updated.every((t) => !visibleTask(t, [deleted])), isTrue);
  });
  test('legacy task definition, overrides and deletion survive local saves and Drive backup restore', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance(),
        repo = LocalTrialRepository.open(await SharedPreferences.getInstance());
    final item = plant('a', property: repo.place.id);
    repo.savePlant(item);
    final legacy = OrchardTask(
      id: 'legacy',
      propertyId: repo.place.id,
      title: 'Prune',
      createdAt: now,
      itemId: item.id,
      dueDate: '2026-11-27',
    );
    repo.saveTask(legacy);
    final base = planForLegacyTask(legacy, [legacy]);
    final edited = editPlan(
      base,
      title: 'Prune carefully',
      notes: '',
      dueDate: '2026-12-01',
      target: 'plants',
      taxonId: apple,
      updateTargets: true,
      includedTargets: [],
      excludedTargets: [],
      now: now,
    );
    final changed = taskDefinitionChanges(
      old: base,
      edited: edited,
      existing: [legacy],
      plants: [item],
      sections: [],
      crops: [],
      taxonomy: starterTaxonomy,
      now: now,
    );
    await repo.saveTaskDefinition(edited, changed);
    expect(repo.tasks.single.id, legacy.id);
    expect(repo.tasks.single.dueDate, '2026-12-01');
    final backup = await TrialBackupStore(prefs, repo).export();
    final reopened = LocalTrialRepository.open(
      prefs,
      snapshot: BackupArchive.decode(backup)
          .records[LocalTrialRepository.storageKey],
    );
    final saved = (await reopened.watchTaskPlans(repo.place.id).first).single;
    expect(saved.legacyIds, [legacy.id]);
    expect(saved.taxonId, apple);
    expect(planForTask(reopened.tasks.single, [saved])?.id, saved.id);
    await reopened.saveTaskDefinition(deletedTaskPlan(saved), [
      reopened.tasks.single.withStatus(TaskStatus.deleted),
    ]);
    final restarted = LocalTrialRepository.open(prefs);
    expect(
      (await restarted.watchTaskPlans(repo.place.id).first).single.deleted,
      isTrue,
    );
  });
  test('new mapping fields round-trip and Firestore batches preserve immutable legacy entries', () async {
    SharedPreferences.setMockInitialValues({});
    final db = FakeFirebaseFirestore(),
        repo = FirestoreOrchardRepository(
          db,
          await SharedPreferences.getInstance(),
        );
    final p = plan(),
        edited = editPlan(
          p,
          title: p.title,
          notes: '',
          dueDate: '2027-01-01',
          target: 'plants',
          taxonId: pear,
          updateTargets: true,
          includedTargets: ['p:a'],
          excludedTargets: ['p:b'],
          now: now,
        );
    final mapped = WorkMapping.readPlan('p', 'plan', WorkMapping.plan(edited));
    expect(mapped.scheduleId, edited.scheduleId);
    expect(mapped.currentKey, p.dueDate);
    expect(mapped.excludedTargets, ['p:b']);
    final t = OrchardTask(
      id: 't',
      propertyId: 'p',
      title: 'Prune',
      createdAt: now,
      planId: 'plan',
      occurrenceOn: mapped.currentKey,
      membershipExcluded: true,
    );
    await repo.saveTaskDefinition(mapped, [t]);
    final rows = await repo
        .watchTasks('p')
        .firstWhere((s) => s.value.isNotEmpty);
    expect(rows.value.single.membershipExcluded, isTrue);
    expect(
      FirestoreMapping.taskFromMap(
        'p',
        't',
        FirestoreMapping.taskToMap(t),
      ).membershipExcluded,
      isTrue,
    );
    final old = WorkMapping.plan(p)
      ..remove('includedTargets')
      ..remove('excludedTargets');
    expect(WorkMapping.readPlan('p', 'plan', old).deleted, isFalse);
  });
  test(
    'whole-task deletion retains actual completion activities through restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance(),
          repo = LocalTrialRepository.open(
            await SharedPreferences.getInstance(),
          );
      final item = plant('a', property: repo.place.id);
      repo.savePlant(item);
      final task = OrchardTask(
        id: 'task',
        propertyId: repo.place.id,
        title: 'Prune',
        createdAt: now,
        itemId: item.id,
        eventType: ActivityType.pruning,
      );
      repo.saveTask(task);
      OrchardCommands(
        repo,
        starterTaxonomy,
      ).changeTaskStatus(task, TaskStatus.completed, repo.place.ownerId);
      final base = planForLegacyTask(repo.tasks.single, repo.tasks),
          removed = deletedTaskPlan(
            planForLegacyTask(repo.tasks.single, repo.tasks),
          );
      final payload = taskDefinitionChanges(
        old: base,
        edited: removed,
        existing: repo.tasks,
        plants: [item],
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        now: now,
      );
      await repo.saveTaskDefinition(removed, payload);
      final reopened = LocalTrialRepository.open(prefs);
      expect(reopened.events.single.type, ActivityType.pruning);
      expect(reopened.tasks.single.status, TaskStatus.completed);
      expect(visibleTask(reopened.tasks.single, [removed]), isFalse);
    },
  );
  test(
    'reanchoring does not duplicate a target already completed on that date',
    () {
      final p = plan();
      final plants = [plant('a')];
      final first = expand(p, [], plants);
      final later = expand(p, first, plants, at: DateTime(2026, 12, 4));
      final existing = [
        ...first,
        later.single.withStatus(TaskStatus.completed, now: now),
      ];
      final edited = editPlan(
        p,
        title: p.title,
        notes: '',
        dueDate: '2026-12-04',
        now: now,
      );
      final updated = apply(existing, changes(p, edited, existing, plants));
      expect(updated.first.membershipExcluded, isTrue);
      final projection = projectedTaskEntries(
        plans: [edited],
        tasks: updated,
        plants: plants,
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        through: now,
      );
      expect(taskCalendarEvents(projection), hasLength(1));
      expect(expand(edited, updated, plants), isEmpty);
    },
  );
}
