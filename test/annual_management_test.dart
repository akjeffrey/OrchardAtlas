import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/landscape_mapping.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/plant_listing.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/work.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalTrialRepository repo;
  late SharedPreferences prefs;
  late ManagedPlant plant;
  late CropPlanting crop;
  final apple = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Apple (Malus)',
  );
  final gala = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Gala');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = LocalTrialRepository.open(prefs);
    repo.saveSection(
      OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.001)],
        createdAt: DateTime(2026),
      ),
    );
    plant = OrchardCommands(repo, starterTaxonomy).addPlant(
      place: repo.place,
      name: 'Gala',
      taxonId: gala.id,
      location: Coordinates(51.01, 1.01),
      sectionId: 'row',
      rowOrder: 4,
      plantingDate: DateTime(2020),
      authorId: LocalTrialRepository.userId,
      notes: 'Keep notes',
    );
    crop = CropPlanting(
      id: 'crop',
      propertyId: repo.place.id,
      sectionId: 'row',
      taxonId: gala.id,
      label: 'Seasonal apple',
      season: '2026',
      createdAt: DateTime(2026),
      plantedOn: '2026-01-01',
      notes: 'Crop notes',
    );
    repo.saveCrop(crop);
  });
  test('annual/perennial management changes retain record IDs, all history, metadata and task targets through restore', () async {
    final task = OrchardTask(
      id: 'task',
      propertyId: repo.place.id,
      title: 'Prune',
      itemId: plant.id,
      createdAt: DateTime(2026),
    );
    final cropTask = OrchardTask(
      id: 'crop-task',
      propertyId: repo.place.id,
      title: 'Water',
      cropId: crop.id,
      createdAt: DateTime(2026),
    );
    repo.saveTask(task);
    repo.saveTask(cropTask);
    repo.appendCropHarvest(
      CropHarvest(
        id: 'harvest',
        propertyId: repo.place.id,
        cropId: crop.id,
        activityDate: '2026-06-01',
        harvest: Harvest(5, HarvestUnit.kg),
        recordedAt: DateTime(2026, 6, 1),
      ),
    );
    final originalEvent = repo.events.single;
    expect(
      () => plant.copyWith(lifeCycle: PlantLifeCycle.annual),
      throwsArgumentError,
    );
    repo.updatePlant(
      plant.copyWith(lifeCycle: PlantLifeCycle.annual, season: '2026'),
    );
    repo.saveCrop(crop.withLifeCycle(PlantLifeCycle.perennial));
    expect(repo.plants.single.lifeCycle, PlantLifeCycle.annual);
    expect(repo.plants.single.season, '2026');
    expect(repo.plants.single.template.lifeCycle, PlantLifeCycle.annual);
    expect(repo.plants.single.template.season, '2026');
    expect(repo.plants.single.location.latitude, plant.location.latitude);
    expect(repo.plants.single.rowOrder, 4);
    expect(repo.plants.single.notes, 'Keep notes');
    expect(repo.events.single.id, originalEvent.id);
    expect(repo.tasks.map((t) => (t.itemId, t.cropId)), [
      (plant.id, null),
      (null, crop.id),
    ]);
    final backup = await TrialBackupStore(prefs, repo).export();
    await TrialBackupStore(prefs, repo).restore(backup);
    final restarted = LocalTrialRepository.open(prefs);
    expect(restarted.plants.single.lifeCycle, PlantLifeCycle.annual);
    expect(restarted.crops.single.lifeCycle, PlantLifeCycle.perennial);
    expect(restarted.cropHarvests.single.harvest.quantity, 5);
    restarted.updatePlant(
      restarted.plants.single.copyWith(lifeCycle: PlantLifeCycle.perennial),
    );
    restarted.saveCrop(
      restarted.crops.single.withLifeCycle(PlantLifeCycle.annual),
    );
    expect(restarted.plants.single.id, plant.id);
    expect(restarted.plants.single.plantedOn, '2020-01-01');
    expect(restarted.crops.single.id, crop.id);
    expect(restarted.crops.single.notes, 'Crop notes');
    expect(restarted.tasks, hasLength(2));
    expect(restarted.events.single.id, originalEvent.id);
  });
  test('ended seasons can change management without reopening or rewriting their history', () async {
    repo.saveCrop(crop.finish(CropStatus.ended));
    final ended = repo.crops.single;
    repo.saveCrop(ended.withLifeCycle(PlantLifeCycle.perennial));
    expect(repo.crops.single.status, CropStatus.ended);
    expect(repo.crops.single.createdAt, ended.createdAt);
    expect(repo.crops.single.season, ended.season);
    final entries = plantEntries(repo.plants, repo.crops, repo.sections);
    expect(
      entries.where((e) => e.cropRecord).single.plant.lifeCycle,
      PlantLifeCycle.perennial,
    );
    expect(
      entries.where((e) => e.cropRecord).single.plant.status,
      ItemStatus.archived,
    );
    expect(() => repo.saveCrop(crop), throwsArgumentError);
  });
  test('native mappings keep lifecycle defaults backward compatible and preserve both conversion directions', () async {
    final legacyPlant = FirestoreMapping.plantToMap(plant)
      ..remove('lifeCycle')
      ..remove('season');
    expect(
      FirestoreMapping.plantFromMap(
        repo.place.id,
        plant.id,
        legacyPlant,
      ).lifeCycle,
      PlantLifeCycle.perennial,
    );
    final legacyCrop = LandscapeMapping.crop(crop)..remove('lifeCycle');
    expect(
      LandscapeMapping.readCrop(repo.place.id, crop.id, legacyCrop).lifeCycle,
      PlantLifeCycle.annual,
    );
    final firestore = FakeFirebaseFirestore();
    final remote = FirestoreOrchardRepository(firestore, prefs);
    remote.savePlant(plant);
    remote.updatePlant(
      plant.copyWith(lifeCycle: PlantLifeCycle.annual, season: '2026'),
    );
    expect(
      (await remote.watchPlants(repo.place.id).first).value.single.lifeCycle,
      PlantLifeCycle.annual,
    );
    remote.saveCrop(crop.withLifeCycle(PlantLifeCycle.perennial));
    expect(
      (await remote.watchCrops(repo.place.id).first).value.single.lifeCycle,
      PlantLifeCycle.perennial,
    );
  });
  test('group/type matching includes perennial and seasonal plants, late arrivals and separate completion IDs', () {
    final group = starterTaxonomy.ancestry(apple.id).first;
    for (final taxonId in [group.id, apple.id, gala.id]) {
      final plan = TaskPlan(
        id: 'plan',
        propertyId: repo.place.id,
        title: 'Care',
        target: 'plants',
        taxonId: taxonId,
        createdAt: DateTime(2026),
        dueDate: '2026-01-01',
      );
      final first = expandPlans(
        plans: [plan],
        existing: [],
        plants: [plant],
        sections: repo.sections,
        crops: [crop],
        taxonomy: starterTaxonomy,
        now: DateTime(2026),
      );
      expect(first, hasLength(2));
      expect(first.map((t) => t.id).toSet(), hasLength(2));
      final later = ManagedPlant(
        id: 'late',
        propertyId: repo.place.id,
        name: 'Late',
        taxonId: gala.id,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
      );
      final extra = expandPlans(
        plans: [plan],
        existing: first,
        plants: [plant, later],
        sections: repo.sections,
        crops: [crop.withLifeCycle(PlantLifeCycle.perennial)],
        taxonomy: starterTaxonomy,
        now: DateTime(2026),
      );
      expect(extra.single.itemId, 'late');
    }
    final collision = CropPlanting(
      id: plant.id,
      propertyId: repo.place.id,
      sectionId: 'row',
      taxonId: gala.id,
      label: 'Imported',
      season: '2026',
      createdAt: DateTime(2026),
    );
    final plan = TaskPlan(
      id: 'plan',
      propertyId: repo.place.id,
      title: 'Care',
      target: 'plants',
      taxonId: apple.id,
      createdAt: DateTime(2026),
    );
    final both = expandPlans(
      plans: [plan],
      existing: [],
      plants: [plant],
      sections: repo.sections,
      crops: [collision],
      taxonomy: starterTaxonomy,
      now: DateTime(2026),
    );
    expect(both.map((t) => t.id).toSet(), hasLength(2));
  });
}
