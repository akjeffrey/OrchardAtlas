import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/icon_mapping.dart';
import 'package:orchard_atlas/data/landscape_mapping.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/work.dart';

import 'support/icon_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LocalTrialRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = LocalTrialRepository.open(prefs);
  });
  final type = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Apple (Malus)',
  );
  final variety = starterTaxonomy.taxa.firstWhere(
    (t) => t.name == 'Domestic apple',
  );
  Taxon edited(
    Taxon old, {
    String? name,
    String? icon,
    PlantSymbol? symbol,
    bool? override,
  }) => Taxon(
    id: old.id,
    name: name ?? old.name,
    rank: old.rank,
    parentId: old.parentId,
    scientificName: old.scientificName,
    symbol: symbol ?? old.symbol,
    customIconId: icon,
    iconOverride: override,
  );
  test(
    'PNG validation rejects oversized dimensions, corrupt and truncated bytes',
    () {
      final icon = MapIcon(id: 'icon', name: 'Pear', png: iconPng());
      expect(icon.png, iconPng());
      expect(() => icon.png[0] = 0, throwsUnsupportedError);
      final huge = Uint8List.fromList(iconPng());
      ByteData.sublistView(huge).setUint32(16, 100000);
      final corrupt = Uint8List.fromList(iconPng())..[35] ^= 1;
      for (final bytes in [
        Uint8List(0),
        Uint8List(40000),
        huge,
        corrupt,
        Uint8List.sublistView(iconPng(), 0, 33),
      ]) {
        expect(
          () => MapIcon(id: 'bad', name: 'Bad', png: bytes),
          throwsFormatException,
        );
      }
      expect(
        () => IconMapping.read('bad', {
          'schemaVersion': 1,
          'name': 'Bad',
          'png': 'x' * 50000,
        }),
        throwsFormatException,
      );
    },
  );
  test('classification edits preserve IDs, task targets, planting events and orchard isolation', () async {
    final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      plantingDate: DateTime(2020, 4, 10),
      authorId: LocalTrialRepository.userId,
    );
    repo.saveTaskPlan(
      TaskPlan(
        id: 'plan',
        propertyId: repo.place.id,
        title: 'Prune apples',
        createdAt: DateTime(2026),
        target: 'plants',
        taxonId: type.id,
      ),
    );
    final events = repo.events.map((e) => e.id).toList();
    final icon = MapIcon(id: 'icon', name: 'Apple icon', png: iconPng());
    repo.saveIcon(repo.place.id, icon);
    repo.saveTaxon(
      repo.place.id,
      edited(type, name: 'Apple', icon: icon.id, override: true),
    );
    repo.saveTaxon(repo.place.id, edited(variety, name: 'Standard apple'));
    final taxonomy = orchardTaxonomy(repo.taxa);
    expect(taxonomy.iconFor(variety.id).customIconId, icon.id);
    expect(taxonomy.ancestry(variety.id).map((t) => t.name), contains('Apple'));
    expect(repo.plants.single.taxonId, plant.taxonId);
    expect(repo.events.map((e) => e.id), events);
    expect(
      (await repo.watchTaskPlans(repo.place.id).first).single.taxonId,
      type.id,
    );
    final other = await repo.createPlace(
      LocalTrialRepository.userId,
      'Other orchard',
    );
    expect(await repo.watchIcons(other.id).first, isEmpty);
    expect(await repo.watchTaxa(other.id).first, isEmpty);
    expect(
      () => repo.saveTaxon(
        repo.place.id,
        Taxon(id: variety.id, name: 'Moved', rank: TaxonRank.group),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.saveTaxon(repo.place.id, edited(type, name: 'Pear (Pyrus)')),
      throwsArgumentError,
    );
    repo.saveTaxon(
      repo.place.id,
      edited(variety, symbol: PlantSymbol.pear, override: true),
    );
    expect(
      orchardTaxonomy(repo.taxa).iconFor(variety.id).symbol,
      PlantSymbol.pear,
    );
    repo.saveTaxon(repo.place.id, edited(variety, override: false));
    expect(
      orchardTaxonomy(repo.taxa).iconFor(variety.id).customIconId,
      icon.id,
    );
    await repo.flushForBackup();
    final restarted = LocalTrialRepository.open(prefs);
    expect(orchardTaxonomy(restarted.taxa).byId(type.id).name, 'Apple');
    expect(restarted.icons.single.png, iconPng());
  });
  test(
    'icon mappings and assignments survive complete offline backup/restore',
    () async {
      final icon = MapIcon(
        id: 'icon',
        name: 'Transparent symbol',
        png: iconPng(),
      );
      repo.saveIcon(repo.place.id, icon);
      repo.saveTaxon(
        repo.place.id,
        edited(variety, icon: icon.id, override: true),
      );
      final row = OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Mixed row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.01)],
        createdAt: DateTime(2026),
        customIconId: icon.id,
      );
      repo.saveSection(row);
      expect(
        LandscapeMapping.readSection(
          repo.place.id,
          row.id,
          LandscapeMapping.section(row),
        ).customIconId,
        icon.id,
      );
      expect(
        FirestoreMapping.taxonFromMap(
          variety.id,
          FirestoreMapping.taxonToMap(repo.taxa.single),
        ).customIconId,
        icon.id,
      );
      final backup = await TrialBackupStore(prefs, repo).export();
      SharedPreferences.setMockInitialValues({});
      final newPrefs = await SharedPreferences.getInstance();
      final empty = LocalTrialRepository.open(newPrefs);
      await TrialBackupStore(newPrefs, empty).restore(backup);
      final restored = LocalTrialRepository.open(newPrefs);
      expect(restored.icons.single.png, iconPng());
      expect(restored.sections.single.customIconId, icon.id);
      expect(restored.taxa.single.customIconId, icon.id);
      final archive = BackupArchive.decode(backup);
      final snapshot = jsonDecode(
        archive.records[LocalTrialRepository.storageKey]!,
      ) as Map<String, dynamic>;
      snapshot['icons'] = [];
      final broken = BackupArchive(DateTime.now(), {
        ...archive.records,
        LocalTrialRepository.storageKey: jsonEncode(snapshot),
      }).encode();
      final before = newPrefs.getString(LocalTrialRepository.storageKey);
      await expectLater(
        TrialBackupStore(newPrefs, restored).restore(broken),
        throwsFormatException,
      );
      expect(newPrefs.getString(LocalTrialRepository.storageKey), before);
      final legacy = FirestoreMapping.taxonFromMap(variety.id, {
        'schemaVersion': 1,
        'name': 'Old',
        'rank': 'species',
        'parentId': type.id,
        'symbol': 'apple',
      });
      expect(legacy.customIconId, isNull);
    },
  );
  test('deletion tombstones preserve inherited assignments and all records through restore', () async {
    final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: variety.id,
      location: Coordinates(51, 1),
      plantingDate: DateTime(2020),
      authorId: LocalTrialRepository.userId,
    );
    repo.saveIcon(
      repo.place.id,
      MapIcon(id: 'icon', name: 'Apple icon', png: iconPng()),
    );
    repo.saveTaxon(repo.place.id, edited(type, icon: 'icon', override: true));
    repo.saveSection(
      OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.01)],
        createdAt: DateTime(2026),
        customIconId: 'icon',
      ),
    );
    repo.deleteIcon(repo.place.id, 'icon');
    expect(repo.icons.single.deleted, isTrue);
    expect(repo.icons.single.png, isEmpty);
    expect(orchardTaxonomy(repo.taxa).iconFor(variety.id).customIconId, 'icon');
    expect(repo.plants.single.id, plant.id);
    expect(repo.events.single.type, ActivityType.planting);
    expect(
      () => repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'icon', name: 'Revive', png: iconPng()),
      ),
      throwsStateError,
    );
    final backup = await TrialBackupStore(prefs, repo).export();
    await TrialBackupStore(prefs, repo).restore(backup);
    final reopened = LocalTrialRepository.open(prefs);
    expect(reopened.icons.single.deleted, isTrue);
    expect(reopened.icons.single.png, isEmpty);
    expect(reopened.sections.single.customIconId, 'icon');
    expect(reopened.plants.single.id, plant.id);
    expect(reopened.events.single.type, ActivityType.planting);
    expect(
      () => IconMapping.read('icon', {
        'schemaVersion': 1,
        'name': 'Deleted icon',
        'deleted': true,
        'png': base64Encode(iconPng()),
      }),
      throwsFormatException,
    );
  });
  test('rename preserves assignments and image through offline backup/restore and rejects deleted IDs', () async {
    repo.saveIcon(
      repo.place.id,
      MapIcon(id: 'icon', name: 'Before', png: iconPng()),
    );
    repo.saveTaxon(repo.place.id, edited(type, icon: 'icon', override: true));
    repo.saveSection(
      OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.01)],
        createdAt: DateTime(2026),
        customIconId: 'icon',
      ),
    );
    repo.renameIcon(repo.place.id, 'icon', '  After  ');
    expect(repo.icons.single.name, 'After');
    expect(repo.icons.single.png, iconPng());
    expect(repo.taxa.single.customIconId, 'icon');
    expect(repo.sections.single.customIconId, 'icon');
    expect(
      () => repo.renameIcon(repo.place.id, 'icon', ''),
      throwsArgumentError,
    );
    expect(
      () => repo.renameIcon(repo.place.id, 'icon', 'x' * 501),
      throwsArgumentError,
    );
    final backup = await TrialBackupStore(prefs, repo).export();
    await TrialBackupStore(prefs, repo).restore(backup);
    final reopened = LocalTrialRepository.open(prefs);
    expect(reopened.icons.single.name, 'After');
    expect(reopened.icons.single.png, iconPng());
    reopened.deleteIcon(reopened.place.id, 'icon');
    expect(
      () => reopened.renameIcon(reopened.place.id, 'icon', 'Revive'),
      throwsStateError,
    );
    expect(reopened.icons.single.deleted, isTrue);
  });
  test('Firestore adapter updates stable taxonomy IDs and streams self-contained icon data', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirestoreOrchardRepository(firestore, prefs);
    final place = await repository.openDefaultPlace('user');
    final icon = MapIcon(id: 'icon', name: 'Pear', png: iconPng());
    repository.saveIcon(place.id, icon);
    expect((await repository.watchIcons(place.id).first).single.png, iconPng());
    repository.renameIcon(place.id, icon.id, '  Renamed  ');
    final renamed = (await repository.watchIcons(place.id).first).single;
    expect(renamed.name, 'Renamed');
    expect(renamed.png, iconPng());
    repository.deleteIcon(place.id, icon.id);
    final deleted = (await repository.watchIcons(place.id).first).single;
    expect(deleted.deleted, isTrue);
    expect(deleted.png, isEmpty);
    repository.saveTaxon(
      place.id,
      edited(variety, name: 'Renamed', icon: icon.id, override: true),
    );
    expect((await repository.watchTaxa(place.id).first).single.id, variety.id);
    repository.saveTaxon(
      place.id,
      edited(variety, name: 'Renamed twice', icon: icon.id, override: true),
    );
    expect(
      (await repository.watchTaxa(place.id).first).single.name,
      'Renamed twice',
    );
    expect(
      (await firestore
              .collection('properties')
              .doc(place.id)
              .collection('taxa')
              .get())
          .docs,
      hasLength(1),
    );
  });
}
