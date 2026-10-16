import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/map_view_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/orchards.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<SharedPreferences> preferences() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('two trial orchards isolate records and retain last selection after restart', () async {
    final prefs = await preferences();
    final repo = LocalTrialRepository.open(prefs);
    final first = repo.place;
    final second = await repo.createPlace(
      LocalTrialRepository.userId,
      'North orchard',
    );
    final commands = OrchardCommands(repo, starterTaxonomy);
    final taxon = starterTaxonomy.taxa.firstWhere(
      (t) => t.rank == TaxonRank.species,
    );
    for (final p in [first, second]) {
      final plant = commands.addPlant(
        place: p,
        name: p.name,
        taxonId: taxon.id,
        location: Coordinates(51, 1),
      );
      commands.record(
        place: p,
        itemId: plant.id,
        authorId: LocalTrialRepository.userId,
        type: ActivityType.note,
        date: DateTime(2026),
        notes: p.name,
      );
      final section = OrchardSection(
        id: 'section-${p.id}',
        propertyId: p.id,
        name: p.name,
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51.001, 1)],
        createdAt: DateTime.utc(2026),
      );
      repo.saveSection(section);
      repo.saveTask(
        OrchardTask(
          id: 'task-${p.id}',
          propertyId: p.id,
          title: 'Prune',
          itemId: plant.id,
          createdAt: DateTime.utc(2026),
        ),
      );
      repo.saveTaxon(
        p.id,
        Taxon(
          id: 'custom-${p.id}',
          name: p.name,
          rank: TaxonRank.cultivar,
          parentId: taxon.id,
          symbol: PlantSymbol.tree,
        ),
      );
      final crop = CropPlanting(
        id: 'crop-${p.id}',
        propertyId: p.id,
        sectionId: section.id,
        taxonId: taxon.id,
        label: p.name,
        season: '2026',
        createdAt: DateTime.utc(2026),
      );
      repo.saveCrop(crop);
      repo.appendCropHarvest(
        CropHarvest(
          id: 'harvest-${p.id}',
          propertyId: p.id,
          cropId: crop.id,
          activityDate: '2026-10-16',
          recordedAt: DateTime.utc(2026, 10, 16),
          harvest: Harvest(2, HarvestUnit.kg),
        ),
      );
      await repo.watchPlants(p.id).firstWhere((s) => !s.hasPendingWrites);
    }
    await repo.selectPlace(LocalTrialRepository.userId, second.id);
    final restarted = LocalTrialRepository.open(prefs);
    expect(
      (await restarted.openDefaultPlace(LocalTrialRepository.userId)).id,
      second.id,
    );
    expect(
      (await restarted.watchPlaces(LocalTrialRepository.userId).first).length,
      2,
    );
    for (final p in [first, second]) {
      final plants = (await restarted.watchPlants(p.id).first).value;
      expect(plants.single.name, p.name);
      expect(
        (await restarted.watchEvents(p.id, plants.single.id).first)
            .value
            .single
            .notes,
        p.name,
      );
      expect(
        (await restarted.watchTasks(p.id).first).value.single.propertyId,
        p.id,
      );
      expect(
        (await restarted.watchSections(p.id).first).value.single.propertyId,
        p.id,
      );
      expect(
        (await restarted.watchCrops(p.id).first).value.single.propertyId,
        p.id,
      );
      expect(
        (await restarted.watchCropHarvests(p.id).first).value.single.propertyId,
        p.id,
      );
      expect((await restarted.watchTaxa(p.id).first).single.name, p.name);
    }
    await expectLater(
      repo.selectPlace('another-user', second.id),
      throwsStateError,
    );
    await expectLater(
      repo.selectPlace(LocalTrialRepository.userId, 'unknown'),
      throwsArgumentError,
    );
    final firstPlant = (await repo.watchPlants(first.id).first).value.single;
    expect(
      () => commands.record(
        place: second,
        itemId: firstPlant.id,
        authorId: LocalTrialRepository.userId,
        type: ActivityType.note,
        date: DateTime(2026),
        notes: 'wrong',
      ),
      throwsStateError,
    );
  });

  test(
    'default views survive restart and are scoped by user and orchard',
    () async {
      final prefs = await preferences();
      final store = DeviceMapViewRepository(prefs);
      await store.save(
        'alice',
        'north',
        OrchardMapView(
          center: Coordinates(51, 1),
          zoom: 16.5,
          bearing: 80,
          tilt: 30,
          fullScreen: true,
        ),
      );
      await store.save(
        'alice',
        'south',
        OrchardMapView(center: Coordinates(52, 2), zoom: 18),
      );
      final restarted = DeviceMapViewRepository(prefs);
      final view = (await restarted.load('alice', 'north'))!;
      expect(view.center.latitude, 51);
      expect(view.zoom, 16.5);
      expect(view.bearing, 80);
      expect(view.tilt, 30);
      expect(view.fullScreen, isTrue);
      expect((await restarted.load('alice', 'south'))!.center.latitude, 52);
      expect(await restarted.load('bob', 'north'), isNull);
      expect(await restarted.load('alice', 'unknown'), isNull);
      await prefs.setString('map-default:alice:broken', '{bad');
      expect(await restarted.load('alice', 'broken'), isNull);
      expect(
        () => OrchardMapView(center: Coordinates(0, 0), zoom: double.nan),
        throwsArgumentError,
      );
    },
  );

  test('Firestore orchard creation/selection and plant queries are owner/property scoped', () async {
    final prefs = await preferences();
    final firestore = FakeFirebaseFirestore();
    final repo = FirestoreOrchardRepository(firestore, prefs);
    final first = await repo.openDefaultPlace('alice');
    final second = await repo.createPlace('alice', 'North orchard');
    await repo.selectPlace('alice', second.id);
    final other = await repo.createPlace('bob', 'Other user');
    await expectLater(repo.selectPlace('alice', other.id), throwsStateError);
    expect((await repo.watchPlaces('alice').first).map((p) => p.id).toSet(), {
      first.id,
      second.id,
    });
    final commands = OrchardCommands(repo, starterTaxonomy);
    final taxon = starterTaxonomy.taxa.firstWhere(
      (t) => t.rank == TaxonRank.species,
    );
    commands.addPlant(
      place: first,
      name: 'South apple',
      taxonId: taxon.id,
      location: Coordinates(51, 1),
    );
    commands.addPlant(
      place: second,
      name: 'North apple',
      taxonId: taxon.id,
      location: Coordinates(52, 2),
    );
    expect(
      (await repo.watchPlants(first.id).first).value.single.name,
      'South apple',
    );
    expect(
      (await repo.watchPlants(second.id).first).value.single.name,
      'North apple',
    );
    final restarted = FirestoreOrchardRepository(firestore, prefs);
    expect((await restarted.openDefaultPlace('alice')).id, second.id);
  });
}
