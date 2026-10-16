import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/filters.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cultivar = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Honeycrisp',
  );
  ManagedPlant plant({
    ItemStatus status = ItemStatus.active,
    String? date = '2022-04-10',
  }) => ManagedPlant(
    id: 'p',
    propertyId: 'place',
    name: 'Row A',
    taxonId: cultivar.id,
    location: Coordinates(51, 1),
    createdAt: DateTime.utc(2026),
    plantedOn: date,
    rootstock: 'M.111',
    nursery: 'Local nursery',
    notes: 'South slope',
    status: status,
    accuracyMeters: 4,
  );
  test('similar plant templates carry date and source but retain no unique identity or history', () {
    final template = plant().template;
    expect(template.plantedOn, '2022-04-10');
    expect(template.rootstock, 'M.111');
    expect(template.nursery, 'Local nursery');
    expect(plant(date: null).template.plantedOn, isNull);
  });
  test(
    'parent classification, planting year, status and text filters combine',
    () {
      final apple = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Apple (Malus)',
      );
      final filter = PlantFilter(taxonId: apple.id, year: 2022, query: 'm.111');
      expect(
        filter.apply([
          plant(),
          plant(status: ItemStatus.archived),
          plant(date: null),
        ], starterTaxonomy).length,
        1,
      );
      expect(
        const PlantFilter(query: 'south')
            .apply([plant()], starterTaxonomy)
            .length,
        1,
      );
      expect(
        const PlantFilter(query: 'nursery')
            .apply([plant()], starterTaxonomy)
            .length,
        1,
      );
      expect(
        const PlantFilter(year: 2021).apply([plant()], starterTaxonomy),
        isEmpty,
      );
      expect(starterTaxonomy.descendants(apple.id), contains(cultivar.id));
    },
  );
  test(
    'harvest remains grouped by original unit and selected calendar year',
    () {
      PlantEvent event(String id, double q, HarvestUnit unit, String date) =>
          PlantEvent(
            id: id,
            propertyId: 'place',
            itemId: 'p',
            authorId: 'u',
            type: ActivityType.harvest,
            occurredAt: DateTime.utc(2026),
            activityDate: date,
            recordedAt: DateTime.utc(2026),
            harvest: Harvest(q, unit),
          );
      final totals = harvestByUnit([
        event('a', 13.1, HarvestUnit.lb, '2026-03-01'),
        event('b', 2.4, HarvestUnit.lb, '2026-10-16'),
        event('c', 2, HarvestUnit.kg, '2026-10-16'),
        event('d', 10, HarvestUnit.count, '2026-10-16'),
        event('e', 100, HarvestUnit.lb, '2025-10-16'),
      ], 2026);
      expect(totals[HarvestUnit.lb], closeTo(15.5, 1e-9));
      expect(totals[HarvestUnit.kg], 2);
      expect(totals[HarvestUnit.count], 10);
      expect(totals.containsKey(HarvestUnit.g), isFalse);
    },
  );
  test(
    'task windows include overdue tasks and separate undated upcoming work',
    () {
      OrchardTask task(String? due) => OrchardTask(
        id: 't',
        propertyId: 'p',
        title: 'Prune',
        dueDate: due,
        createdAt: DateTime.utc(2026),
      );
      final now = DateTime(2026, 10, 16, 23);
      expect(taskInWindow(task('2026-10-15'), TaskWindow.today, now), isTrue);
      expect(
        taskInWindow(task('2026-10-18'), TaskWindow.thisWeek, now),
        isTrue,
      );
      expect(
        taskInWindow(task('2026-10-19'), TaskWindow.thisWeek, now),
        isFalse,
      );
      expect(taskInWindow(task(null), TaskWindow.upcoming, now), isTrue);
      expect(taskInWindow(task(null), TaskWindow.today, now), isFalse);
      expect(() => task('2026-02-30'), throwsArgumentError);
    },
  );
  test(
    'plant metadata mapping is backward compatible and validates new fields',
    () {
      final map = FirestoreMapping.plantToMap(plant());
      final read = FirestoreMapping.plantFromMap('place', 'p', map);
      expect(read.template.plantedOn, '2022-04-10');
      expect(read.accuracyMeters, 4);
      expect(read.notes, 'South slope');
      final legacy = Map<String, dynamic>.of(map)
        ..removeWhere(
          (key, _) => [
            'plantedOn',
            'rootstock',
            'nursery',
            'notes',
            'status',
            'accuracyMeters',
          ].contains(key),
        );
      final old = FirestoreMapping.plantFromMap('place', 'p', legacy);
      expect(old.status, ItemStatus.active);
      expect(old.plantedOn, isNull);
      expect(old.rootstock, '');
      expect(
        () => FirestoreMapping.plantFromMap('place', 'p', {
          ...map,
          'accuracyMeters': -1,
        }),
        throwsArgumentError,
      );
      expect(
        () => FirestoreMapping.plantFromMap('place', 'p', {
          ...map,
          'plantedOn': '2026-02-30',
        }),
        throwsArgumentError,
      );
    },
  );
  test('trial restart retains edits, archive, tasks and original planting activity', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTrialRepository.open(prefs);
    final commands = OrchardCommands(repo, starterTaxonomy);
    final first = commands.addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: cultivar.id,
      location: Coordinates(51, 1),
      plantingDate: DateTime(2022, 4, 10),
      authorId: LocalTrialRepository.userId,
      rootstock: 'M.111',
      nursery: 'Orchard nursery',
      accuracyMeters: 7,
    );
    repo.updatePlant(
      first.copyWith(
        name: 'Apple 12',
        notes: 'Renamed',
        status: ItemStatus.archived,
      ),
    );
    final task = OrchardTask(
      id: 'task',
      propertyId: repo.place.id,
      itemId: first.id,
      title: 'Prune',
      dueDate: '2026-10-16',
      createdAt: DateTime.utc(2026),
    );
    repo.saveTask(task);
    repo.saveTask(task.withStatus(TaskStatus.completed));
    await repo.watchTasks(repo.place.id).firstWhere((s) => !s.hasPendingWrites);
    final restarted = LocalTrialRepository.open(prefs);
    expect(restarted.plants.single.name, 'Apple 12');
    expect(restarted.plants.single.status, ItemStatus.archived);
    expect(restarted.plants.single.template.plantedOn, '2022-04-10');
    expect(restarted.tasks.single.status, TaskStatus.completed);
    expect(restarted.tasks.single.itemId, first.id);
    expect(restarted.events.single.activityDate, '2022-04-10');
    restarted.saveTask(restarted.tasks.single.withStatus(TaskStatus.cancelled));
    restarted.updatePlant(
      restarted.plants.single.copyWith(status: ItemStatus.active),
    );
    expect(restarted.plants.single.status, ItemStatus.active);
    expect(restarted.tasks.single.status, TaskStatus.cancelled);
    await restarted
        .watchTasks(repo.place.id)
        .firstWhere((s) => !s.hasPendingWrites);
  });
  test(
    'clearing planting date creates no event, including similar entry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalTrialRepository.open(
        await SharedPreferences.getInstance(),
      );
      final commands = OrchardCommands(repo, starterTaxonomy);
      final first = commands.addPlant(
        place: repo.place,
        name: 'Apple',
        taxonId: cultivar.id,
        location: Coordinates(51, 1),
      );
      expect(first.template.plantedOn, isNull);
      expect(repo.events, isEmpty);
      await repo
          .watchPlants(repo.place.id)
          .firstWhere((s) => !s.hasPendingWrites);
    },
  );
  test(
    'Firestore streams preserve metadata edits and task status mapping',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = FirestoreOrchardRepository(
        FakeFirebaseFirestore(),
        await SharedPreferences.getInstance(),
      );
      final place = await repo.openDefaultPlace('alice');
      final first = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: place,
        name: 'Apple',
        taxonId: cultivar.id,
        location: Coordinates(51, 1),
        plantingDate: DateTime(2022, 4, 10),
        authorId: 'alice',
        rootstock: 'M.111',
      );
      await repo.watchPlants(place.id).firstWhere((s) => s.value.isNotEmpty);
      repo.updatePlant(
        first.copyWith(status: ItemStatus.archived, nursery: 'New nursery'),
      );
      final updated = await repo
          .watchPlants(place.id)
          .firstWhere((s) => s.value.single.status == ItemStatus.archived);
      expect(updated.value.single.plantedOn, '2022-04-10');
      final task = OrchardTask(
        id: 'task',
        propertyId: place.id,
        itemId: first.id,
        title: 'Check tree',
        createdAt: DateTime.utc(2026),
      );
      repo.saveTask(task);
      await repo.watchTasks(place.id).firstWhere((s) => s.value.isNotEmpty);
      repo.saveTask(task.withStatus(TaskStatus.completed));
      final tasks = await repo
          .watchTasks(place.id)
          .firstWhere((s) => s.value.single.status == TaskStatus.completed);
      expect(tasks.value.single.itemId, first.id);
      expect(tasks.value.single.dueDate, isNull);
    },
  );
}
