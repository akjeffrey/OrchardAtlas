import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/filters.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/data/landscape_mapping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 16);
  final polygon = [
    Coordinates(51, 1),
    Coordinates(51.001, 1),
    Coordinates(51.001, 1.001),
    Coordinates(51, 1.001),
  ];
  OrchardSection section(
    String id,
    String property, {
    String? parent,
    SectionKind kind = SectionKind.area,
  }) => OrchardSection(
    id: id,
    propertyId: property,
    name: id,
    kind: kind,
    parentId: parent,
    vertices: kind == SectionKind.row ? polygon.take(2).toList() : polygon,
    createdAt: now,
  );
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  test('geometry rejects degenerate, duplicate, self-crossing and date-line shapes', () {
    for (final points in <List<Coordinates>>[
      [Coordinates(0, 0), Coordinates(1, 1)],
      [Coordinates(0, 0), Coordinates(1, 1), Coordinates(2, 2)],
      [
        Coordinates(0, 0),
        Coordinates(1, 1),
        Coordinates(0, 1),
        Coordinates(1, 0),
      ],
      [Coordinates(0, 0), Coordinates(1, 0), Coordinates(0, 0)],
      [Coordinates(0, 179), Coordinates(1, -179), Coordinates(2, 178)],
    ]) {
      expect(
        () => validateGeometry(SectionKind.area, points),
        throwsArgumentError,
      );
    }
    expect(
      () => validateGeometry(SectionKind.row, [Coordinates(0, 0)]),
      throwsArgumentError,
    );
    expect(
      () => validateGeometry(SectionKind.row, [
        for (var i = 0; i < 41; i++) Coordinates(i.toDouble(), 0),
      ]),
      throwsArgumentError,
    );
    expect(section('bed', 'p').vertices.length, 4);
  });
  test('section hierarchy validates property, parent type and cycles', () {
    final bed = section('bed', 'p'),
        row = section('row', 'p', parent: 'bed', kind: SectionKind.row);
    validateSectionParent(row, [bed]);
    expect(sectionDescendants('bed', [bed, row]), {'bed', 'row'});
    expect(
      () =>
          validateSectionParent(section('bad', 'p', parent: 'row'), [bed, row]),
      throwsArgumentError,
    );
    expect(
      () =>
          validateSectionParent(section('bad', 'other', parent: 'bed'), [bed]),
      throwsArgumentError,
    );
    expect(
      () => validateSectionParent(section('a', 'p', parent: 'b'), [
        section('b', 'p', parent: 'a'),
      ]),
      throwsArgumentError,
    );
  });
  test('group selection includes taxonomy/section descendants and snapshots active members', () async {
    final repo = await repository();
    final bed = section('bed', repo.place.id),
        row = section(
          'row',
          repo.place.id,
          parent: 'bed',
          kind: SectionKind.row,
        );
    repo.saveSection(bed);
    repo.saveSection(row);
    final commands = OrchardCommands(repo, starterTaxonomy);
    final apple = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Apple (Malus)',
    );
    final honey = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Honeycrisp',
    );
    final pear = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'European pear',
    );
    final first = commands.addPlant(
      place: repo.place,
      name: 'Apple 1',
      taxonId: honey.id,
      sectionId: row.id,
      location: Coordinates(51, 1),
    );
    commands.addPlant(
      place: repo.place,
      name: 'Pear',
      taxonId: pear.id,
      sectionId: row.id,
      location: Coordinates(51, 1),
    );
    final archived = commands.addPlant(
      place: repo.place,
      name: 'Old apple',
      taxonId: honey.id,
      sectionId: bed.id,
      location: Coordinates(51, 1),
    );
    repo.updatePlant(archived.copyWith(status: ItemStatus.archived));
    var serial = 0;
    final group = groupPlantTasks(
      propertyId: repo.place.id,
      title: 'Prune apples',
      plants: repo.plants,
      taxonomy: starterTaxonomy,
      sections: repo.sections,
      newId: () => 'id-${++serial}',
      taxonId: apple.id,
      sectionId: bed.id,
    );
    repo.saveTaskGroup(group);
    commands.addPlant(
      place: repo.place,
      name: 'Later apple',
      taxonId: honey.id,
      sectionId: row.id,
      location: Coordinates(51, 1),
    );
    expect(repo.tasks.single.itemId, first.id);
    expect(repo.tasks.single.groupId, 'id-1');
    expect(
      PlantFilter(sectionId: bed.id)
          .apply(repo.plants, starterTaxonomy, sections: repo.sections)
          .length,
      3,
    );
    expect(first.template.sectionId, row.id);
    repo.updatePlant(first.copyWith(clearSection: true));
    expect(repo.plants.first.sectionId, isNull);
    await repo
        .watchPlants(repo.place.id)
        .firstWhere((s) => !s.hasPendingWrites);
  });
  test('member completion dates, skipped status and remaining work persist across restart', () async {
    final repo = await repository();
    final commands = OrchardCommands(repo, starterTaxonomy);
    final species = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Domestic apple',
    );
    for (var i = 0; i < 3; i++) {
      commands.addPlant(
        place: repo.place,
        name: 'Apple $i',
        taxonId: species.id,
        location: Coordinates(51, 1),
      );
    }
    var serial = 0;
    final members = groupPlantTasks(
      propertyId: repo.place.id,
      title: 'Prune apples',
      plants: repo.plants,
      taxonomy: starterTaxonomy,
      sections: [],
      newId: () => 'group-${++serial}',
    );
    repo.saveTaskGroup(members);
    repo.saveTask(
      members[0].withStatus(TaskStatus.completed, now: DateTime(2026, 10, 16)),
    );
    repo.saveTask(members[1].withStatus(TaskStatus.skipped));
    await repo.watchTasks(repo.place.id).firstWhere((s) => !s.hasPendingWrites);
    final restarted = LocalTrialRepository.open(repo.preferences);
    expect(restarted.tasks.map((t) => t.status), [
      TaskStatus.completed,
      TaskStatus.skipped,
      TaskStatus.open,
    ]);
    expect(restarted.tasks.first.completedOn, '2026-10-16');
    restarted.saveTask(restarted.tasks.first.withStatus(TaskStatus.open));
    expect(restarted.tasks.first.completedOn, isNull);
    await restarted
        .watchTasks(repo.place.id)
        .firstWhere((s) => !s.hasPendingWrites);
  });
  test(
    'invalid group submission is atomic and leaves no partial checklist',
    () async {
      final repo = await repository();
      final a = OrchardTask(
        id: 'a',
        propertyId: repo.place.id,
        title: 'Prune',
        itemId: 'missing',
        groupId: 'g',
        createdAt: now,
      );
      expect(() => repo.saveTaskGroup([a]), throwsArgumentError);
      expect(repo.tasks, isEmpty);
    },
  );
  test('seasons and append-only harvests preserve previous crop varieties and units', () async {
    final repo = await repository();
    final bed = section('bed', repo.place.id),
        row = section(
          'row',
          repo.place.id,
          parent: 'bed',
          kind: SectionKind.row,
        );
    repo.saveSection(bed);
    repo.saveSection(row);
    final garlic = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Garlic');
    final old = CropPlanting(
      id: 'old',
      propertyId: repo.place.id,
      sectionId: row.id,
      taxonId: garlic.id,
      label: 'German Extra Hardy',
      season: '2025 autumn',
      plantedOn: '2025-10-10',
      createdAt: now,
    );
    repo.saveCrop(old);
    repo.appendCropHarvest(
      CropHarvest(
        id: 'h1',
        propertyId: repo.place.id,
        cropId: old.id,
        activityDate: '2026-07-10',
        harvest: Harvest(13.1, HarvestUnit.lb),
        recordedAt: now,
      ),
    );
    repo.appendCropHarvest(
      CropHarvest(
        id: 'h2',
        propertyId: repo.place.id,
        cropId: old.id,
        activityDate: '2026-07-11',
        harvest: Harvest(2, HarvestUnit.kg),
        recordedAt: now,
      ),
    );
    repo.saveCrop(old.finish(CropStatus.harvested, date: '2026-07-11'));
    repo.saveCrop(
      CropPlanting(
        id: 'new',
        propertyId: repo.place.id,
        sectionId: row.id,
        taxonId: garlic.id,
        label: 'Music',
        season: '2026 autumn',
        plantedOn: '2026-10-16',
        createdAt: now,
      ),
    );
    await repo.watchCrops(repo.place.id).firstWhere((s) => !s.hasPendingWrites);
    final reopened = LocalTrialRepository.open(repo.preferences);
    expect(reopened.sections.length, 2);
    expect(reopened.crops.map((c) => c.label), ['German Extra Hardy', 'Music']);
    expect(reopened.crops.first.status, CropStatus.harvested);
    expect(reopened.cropHarvests.map((h) => h.harvest.unit), [
      HarvestUnit.lb,
      HarvestUnit.kg,
    ]);
    expect(
      () => reopened.appendCropHarvest(reopened.cropHarvests.first),
      throwsArgumentError,
    );
    expect(
      () => reopened.appendCropHarvest(
        CropHarvest(
          id: 'early',
          propertyId: repo.place.id,
          cropId: 'old',
          activityDate: '2024-01-01',
          harvest: Harvest(1, HarvestUnit.kg),
          recordedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => old.finish(CropStatus.harvested, date: '2024-01-01'),
      throwsArgumentError,
    );
  });
  test('landscape mappings round trip native and local geometry, crops and harvests', () {
    final s = section('bed', 'p');
    final crop = CropPlanting(
      id: 'c',
      propertyId: 'p',
      sectionId: 'bed',
      taxonId: 'garlic',
      label: 'Music',
      season: '2026',
      createdAt: now,
      plantedOn: '2026-01-01',
    );
    final h = CropHarvest(
      id: 'h',
      propertyId: 'p',
      cropId: 'c',
      activityDate: '2026-07-01',
      harvest: Harvest(3, HarvestUnit.count),
      recordedAt: now,
    );
    for (final native in [false, true]) {
      expect(
        LandscapeMapping.readSection(
          'p',
          'bed',
          LandscapeMapping.section(s, native: native),
        ).vertices[1].latitude,
        51.001,
      );
      expect(
        LandscapeMapping.readCrop(
          'p',
          'c',
          LandscapeMapping.crop(crop, native: native),
        ).label,
        'Music',
      );
      expect(
        LandscapeMapping.readHarvest(
          'p',
          'h',
          LandscapeMapping.harvest(h, native: native),
        ).harvest.quantity,
        3,
      );
    }
    final task = OrchardTask(
      id: 't',
      propertyId: 'p',
      title: 'Prune',
      itemId: 'a',
      groupId: 'g',
      groupScope: 'Apple',
      createdAt: now,
    ).withStatus(TaskStatus.completed, now: DateTime(2026, 10, 16));
    expect(
      FirestoreMapping.taskFromMap(
        'p',
        't',
        FirestoreMapping.taskToMap(task),
      ).completedOn,
      '2026-10-16',
    );
  });
  test('Firestore adapter streams sections, seasons, harvests and independent group members', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = FirestoreOrchardRepository(
      FakeFirebaseFirestore(),
      await SharedPreferences.getInstance(),
    );
    final place = await repo.openDefaultPlace('alice');
    repo.saveSection(section('bed', place.id));
    await repo.watchSections(place.id).firstWhere((s) => s.value.isNotEmpty);
    final garlic = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Garlic');
    final crop = CropPlanting(
      id: 'c',
      propertyId: place.id,
      sectionId: 'bed',
      taxonId: garlic.id,
      label: 'Music',
      season: '2026',
      createdAt: now,
    );
    repo.saveCrop(crop);
    await repo.watchCrops(place.id).firstWhere((s) => s.value.isNotEmpty);
    repo.appendCropHarvest(
      CropHarvest(
        id: 'h',
        propertyId: place.id,
        cropId: 'c',
        activityDate: '2026-07-01',
        harvest: Harvest(2, HarvestUnit.kg),
        recordedAt: now,
      ),
    );
    expect(
      (await repo
              .watchCropHarvests(place.id)
              .firstWhere((s) => s.value.isNotEmpty))
          .value
          .single
          .cropId,
      'c',
    );
    final apple = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Domestic apple',
    );
    final commands = OrchardCommands(repo, starterTaxonomy);
    final p = commands.addPlant(
      place: place,
      name: 'Apple',
      taxonId: apple.id,
      location: Coordinates(51, 1),
      sectionId: 'bed',
    );
    await repo.watchPlants(place.id).firstWhere((s) => s.value.isNotEmpty);
    final group = [
      OrchardTask(
        id: 't',
        propertyId: place.id,
        title: 'Prune',
        itemId: p.id,
        groupId: 'g',
        createdAt: now,
      ),
    ];
    repo.saveTaskGroup(group);
    await repo.watchTasks(place.id).firstWhere((s) => s.value.isNotEmpty);
    repo.saveTask(group.single.withStatus(TaskStatus.skipped));
    expect(
      (await repo
              .watchTasks(place.id)
              .firstWhere(
                (s) =>
                    s.value.isNotEmpty &&
                    s.value.single.status == TaskStatus.skipped,
              ))
          .value
          .single
          .groupId,
      'g',
    );
  });
  test(
    'row and seasonal crop groups preserve independent target identities',
    () async {
      final repo = await repository();
      final bed = section('bed', repo.place.id),
          row = section(
            'row',
            repo.place.id,
            parent: 'bed',
            kind: SectionKind.row,
          );
      repo.saveSection(bed);
      repo.saveSection(row);
      final garlic = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Garlic');
      final crop = CropPlanting(
        id: 'crop',
        propertyId: repo.place.id,
        sectionId: row.id,
        taxonId: garlic.id,
        label: 'Music',
        season: '2026',
        createdAt: now,
      );
      repo.saveCrop(crop);
      var serial = 0;
      final rows = groupLayoutTasks(
        propertyId: repo.place.id,
        title: 'Harvest rows',
        sections: repo.sections,
        crops: repo.crops,
        taxonomy: starterTaxonomy,
        newId: () => 'r-${++serial}',
        targetCrops: false,
        sectionId: 'bed',
      );
      repo.saveTaskGroup(rows);
      expect(rows.single.sectionId, 'row');
      final crops = groupLayoutTasks(
        propertyId: repo.place.id,
        title: 'Inspect garlic',
        sections: repo.sections,
        crops: repo.crops,
        taxonomy: starterTaxonomy,
        newId: () => 'c-${++serial}',
        targetCrops: true,
        taxonId: garlic.id,
        sectionId: 'bed',
      );
      repo.saveTaskGroup(crops);
      expect(crops.single.cropId, 'crop');
      repo.saveTask(
        rows.single.withStatus(
          TaskStatus.completed,
          now: DateTime(2026, 10, 16),
        ),
      );
      expect(repo.tasks.last.status, TaskStatus.open);
      await repo
          .watchTasks(repo.place.id)
          .firstWhere((s) => !s.hasPendingWrites);
    },
  );
}
