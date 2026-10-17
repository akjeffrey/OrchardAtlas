import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/landscape_mapping.dart';
import 'package:orchard_atlas/data/map_view_repository.dart';
import 'package:orchard_atlas/data/work_mapping.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/work.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 1, 31);
  final apple = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Apple (Malus)',
  );
  final variety = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Honeycrisp',
  );
  TaskPlan plan({
    RepeatSchedule repeat = RepeatSchedule.none,
    String? due = '2026-01-31',
  }) => TaskPlan(
    id: 'plan',
    propertyId: 'property',
    title: 'Prune apples',
    createdAt: date,
    target: 'plants',
    taxonId: apple.id,
    dueDate: due,
    repeat: repeat,
    eventType: ActivityType.pruning,
  );
  ManagedPlant plant(
    String id, {
    String property = 'property',
    String? section,
    double longitude = 1,
  }) => ManagedPlant(
    id: id,
    propertyId: property,
    name: id,
    taxonId: variety.id,
    location: Coordinates(51, longitude),
    createdAt: date,
    sectionId: section,
  );
  List<OrchardTask> expand(
    TaskPlan p,
    List<ManagedPlant> plants, {
    List<OrchardTask> existing = const [],
    DateTime? now,
  }) => expandPlans(
    plans: [p],
    existing: existing,
    plants: plants,
    sections: [],
    crops: [],
    taxonomy: starterTaxonomy,
    now: now ?? date,
  );
  test(
    'calendar recurrence clamps month ends without drifting or resetting early',
    () {
      final p = plan(repeat: RepeatSchedule.monthly);
      expect(occurrenceDates(p, DateTime(2026, 2, 15)), ['2026-01-31']);
      expect(occurrenceDates(p, DateTime(2026, 3, 31)), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
      ]);
      expect(occurrenceDates(p, DateTime(2025)), ['2026-01-31']);
      final leap = TaskPlan(
        id: 'leap',
        propertyId: 'property',
        title: 'Yearly',
        createdAt: date,
        target: 'property',
        dueDate: '2024-02-29',
        repeat: RepeatSchedule.yearly,
      );
      expect(occurrenceDates(leap, DateTime(2028, 2, 29)), [
        '2024-02-29',
        '2025-02-28',
        '2026-02-28',
        '2027-02-28',
        '2028-02-29',
      ]);
    },
  );
  test('zero-match plans survive mapping and new matches join with stable identities', () {
    final p = WorkMapping.readPlan(
      'property',
      'plan',
      WorkMapping.plan(plan()),
    );
    expect(expand(p, []), isEmpty);
    final first = expand(p, [plant('a')]).single;
    expect(first.itemId, 'a');
    expect(first.id, expand(p, [plant('a')]).single.id);
    expect(
      expand(
        p,
        [plant('a'), plant('b'), plant('foreign', property: 'other')],
        existing: [first.withStatus(TaskStatus.completed)],
      ).map((t) => t.itemId),
      ['b'],
    );
  });
  test('new recurring occurrence is fresh and late plants do not rewrite recorded history', () {
    final p = plan(repeat: RepeatSchedule.monthly);
    final first = expand(p, [
      plant('a'),
    ]).single.withStatus(TaskStatus.completed, now: DateTime(2026, 1, 31));
    final added = expand(
      p,
      [plant('a'), plant('b')],
      existing: [first],
      now: DateTime(2026, 2, 28),
    );
    expect(added.length, 2);
    expect(
      added.every(
        (t) => t.occurrenceOn == '2026-02-28' && t.status == TaskStatus.open,
      ),
      isTrue,
    );
    expect(first.status, TaskStatus.completed);
  });
  test('task default sort is undated then next due then overdue', () {
    OrchardTask task(String id, String? due) => OrchardTask(
      id: id,
      propertyId: 'property',
      title: id,
      createdAt: date,
      dueDate: due,
    );
    final tasks = [
      task('late', '2026-01-30'),
      task('later', '2026-02-10'),
      task('undated', null),
      task('next', '2026-02-01'),
    ];
    tasks.sort((a, b) => compareTasks(a, b, TaskSort.dueDate, date));
    expect(tasks.map((t) => t.id), ['undated', 'next', 'later', 'late']);
  });
  test('legacy beds become Areas preserving identity, geometry and style', () {
    final section = OrchardSection(
      id: 'section',
      propertyId: 'property',
      name: 'My garlic bed',
      kind: SectionKind.area,
      vertices: [
        Coordinates(51, 1),
        Coordinates(51.1, 1),
        Coordinates(51.1, 1.1),
      ],
      createdAt: date,
      color: 0xff123456,
      symbol: PlantSymbol.berry,
    );
    final map = LandscapeMapping.section(section)..['kind'] = 'bed';
    final read = LandscapeMapping.readSection('property', 'section', map);
    expect(read.kind, SectionKind.area);
    expect(read.id, section.id);
    expect(read.name, section.name);
    expect(read.color, section.color);
    expect(read.symbol, section.symbol);
    expect(LandscapeMapping.section(read)['kind'], 'area');
  });
  test('row direction follows endpoints and honors manual order', () {
    final row = OrchardSection(
      id: 'row',
      propertyId: 'property',
      name: 'Blueberries',
      kind: SectionKind.row,
      vertices: [
        Coordinates(51, 1),
        Coordinates(51, 1.1),
        Coordinates(51, 1.2),
      ],
      createdAt: date,
    );
    final first = plant('first', section: 'row', longitude: 1.01),
        last = plant('last', section: 'row', longitude: 1.19);
    expect(orderedRowPlants(row, [last, first]).map((p) => p.id), [
      'first',
      'last',
    ]);
    expect(
      orderedRowPlants(row, [
        last.copyWith(rowOrder: 0),
        first.copyWith(rowOrder: 1),
      ]).map((p) => p.id),
      ['last', 'first'],
    );
    expect(sectionCenter(row).longitude, closeTo(1.1, 1e-9));
  });
  test('offline linked completion is idempotent, reopening preserves manual activities', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTrialRepository.open(prefs);
    final commands = OrchardCommands(repo, starterTaxonomy);
    final p = commands.addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      authorId: LocalTrialRepository.userId,
    );
    final task = OrchardTask(
      id: 'task',
      propertyId: repo.place.id,
      title: 'Prune',
      createdAt: date,
      itemId: p.id,
      eventType: ActivityType.pruning,
    );
    repo.saveTask(task);
    commands.record(
      place: repo.place,
      itemId: p.id,
      authorId: LocalTrialRepository.userId,
      type: ActivityType.pruning,
      date: date,
      notes: 'Manual',
    );
    commands.changeTaskStatus(
      task,
      TaskStatus.completed,
      LocalTrialRepository.userId,
    );
    final completed = repo.tasks.single;
    commands.changeTaskStatus(
      completed,
      TaskStatus.completed,
      LocalTrialRepository.userId,
    );
    expect(repo.events.where((e) => e.taskId == task.id).length, 1);
    commands.changeTaskStatus(
      completed,
      TaskStatus.open,
      LocalTrialRepository.userId,
    );
    expect(repo.events.where((e) => e.taskId == task.id), isEmpty);
    expect(repo.events.single.notes, 'Manual');
    commands.changeTaskStatus(
      repo.tasks.single,
      TaskStatus.completed,
      LocalTrialRepository.userId,
    );
    repo.deleteEvent(repo.events.firstWhere((e) => e.taskId == task.id));
    expect(repo.tasks.single.status, TaskStatus.open);
    await repo.watchTasks(repo.place.id).firstWhere((s) => !s.hasPendingWrites);
    expect(
      LocalTrialRepository.open(prefs).tasks.single.status,
      TaskStatus.open,
    );
  });
  test('offline full plant editing, planting history, ordering and cascade persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTrialRepository.open(prefs);
    expect(repo.place.name, 'Home Orchard');
    final row = OrchardSection(
      id: 'row',
      propertyId: repo.place.id,
      name: 'Row',
      kind: SectionKind.row,
      vertices: [Coordinates(51, 1), Coordinates(51, 1.1)],
      createdAt: date,
    );
    repo.saveSection(row);
    final commands = OrchardCommands(repo, starterTaxonomy);
    final p = commands.addPlant(
      place: repo.place,
      name: 'Tree',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      authorId: LocalTrialRepository.userId,
      sectionId: 'row',
      plantingDate: date,
    );
    final other = commands.addPlant(
      place: repo.place,
      name: 'Outside',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      authorId: LocalTrialRepository.userId,
    );
    repo.updatePlant(
      p.copyWith(
        name: 'Renamed',
        taxonId: apple.id,
        location: Coordinates(52, 2),
        plantedOn: '2025-01-01',
      ),
    );
    repo.saveRowOrder(repo.place.id, 'row', [p.id]);
    await repo.renamePlace(
      LocalTrialRepository.userId,
      repo.place.id,
      'South orchard',
    );
    await repo
        .watchPlants(repo.place.id)
        .firstWhere((s) => !s.hasPendingWrites);
    final restart = LocalTrialRepository.open(prefs);
    expect(restart.place.name, 'South orchard');
    expect(restart.plants.firstWhere((x) => x.id == p.id).taxonId, apple.id);
    expect(restart.plants.firstWhere((x) => x.id == p.id).rowOrder, 0);
    expect(restart.events.single.activityDate, '2025-01-01');
    await restart.deleteSection(repo.place.id, 'row');
    final deleted = LocalTrialRepository.open(prefs);
    expect(deleted.sections, isEmpty);
    expect(deleted.events, isEmpty);
    expect(deleted.plants.single.id, other.id);
    final views = DeviceMapViewRepository(prefs);
    await views.saveTaskSort('user', 'title');
    expect(await DeviceMapViewRepository(prefs).loadTaskSort('user'), 'title');
  });
  test('deleting a section removes its plan and assignments after a plant moved out', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTrialRepository.open(prefs);
    final commands = OrchardCommands(repo, starterTaxonomy);
    repo.saveSection(
      OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.1)],
        createdAt: date,
      ),
    );
    final p = commands.addPlant(
      place: repo.place,
      name: 'Moved tree',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      sectionId: 'row',
    );
    final scoped = TaskPlan(
      id: 'scoped',
      propertyId: repo.place.id,
      title: 'Prune row',
      target: 'plants',
      sectionId: 'row',
      createdAt: date,
      eventType: ActivityType.pruning,
    );
    repo.saveTaskPlan(scoped);
    final task = expandPlans(
      plans: [scoped],
      existing: [],
      plants: repo.plants,
      sections: repo.sections,
      crops: [],
      taxonomy: starterTaxonomy,
      now: date,
    ).single;
    repo.saveTask(task);
    commands.changeTaskStatus(
      task,
      TaskStatus.completed,
      LocalTrialRepository.userId,
    );
    repo.updatePlant(p.copyWith(clearSection: true));
    await repo.deleteSection(repo.place.id, 'row');
    expect(repo.plants.single.id, p.id);
    expect(repo.tasks, isEmpty);
    expect(repo.events, isEmpty);
    expect(await repo.watchTaskPlans(repo.place.id).first, isEmpty);
    expect(LocalTrialRepository.open(prefs).tasks, isEmpty);
  });
}
