import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/seed_trays.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/data/seed_tray_mapping.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 1, 1);
  final taxon = starterTaxonomy.taxa
      .where((t) => t.rank == TaxonRank.species)
      .first
      .id;
  SeedTray tray(String property, {String id = 'tray'}) => SeedTray(
    id: id,
    propertyId: property,
    name: 'Seeds',
    rows: 2,
    columns: 2,
    createdAt: now,
  );
  TrayAssignment assignment() => TrayAssignment(
    label: 'Tomato',
    taxonId: taxon,
    kind: TrayContentKind.seed,
    assignedAt: now,
    plantedOn: '2026-12-31',
    transplantAfterDays: 14,
    packetFrontId: 'front',
    packetBackId: 'back',
  );
  List<SeedPacketPhoto> photos() => [
    for (final id in ['front', 'back'])
      SeedPacketPhoto(
        id: id,
        authorId: 'local-phone-trial',
        image: Uint8List.fromList([1, 2, 3]),
        thumbnail: Uint8List.fromList([1]),
      ),
  ];
  Future<SharedPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('expected transplant dates cross year boundaries and actual dates preserve planting/packet identity', () {
    final a = assignment();
    expect(a.expectedTransplantOn, '2027-01-14');
    expect(a.isTransplanted, isFalse);
    final t = a.withTransplantDate('2027-01-20');
    expect(t.isTransplanted, isTrue);
    expect(t.packetFrontId, 'front');
    expect(t.plantedOn, a.plantedOn);
    expect(t.withTransplantDate(null).isTransplanted, isFalse);
    expect(() => a.withTransplantDate('2026-12-01'), throwsArgumentError);
    expect(
      () => TrayAssignment(
        label: 'X',
        taxonId: taxon,
        kind: TrayContentKind.seed,
        assignedAt: now,
        transplantAfterDays: -1,
      ),
      throwsArgumentError,
    );
    final old = SeedTrayMapping.cell(tray('p'), TrayPosition(1, 1), a)
      ..removeWhere(
        (k, _) => [
          'plantedOn',
          'transplantAfterDays',
          'transplantedOn',
          'packetFrontId',
          'packetBackId',
        ].contains(k),
      );
    expect(SeedTrayMapping.readCell(old).value.plantedOn, isNull);
  });
  test('shared front/back photos, transplant dates and deletion survive local restart and Drive restore without touching other trays', () async {
    final storage = await prefs(),
        repo = LocalTrialRepository.open(storage),
        t = tray(repo.place.id);
    await repo.createSeedTray(t);
    await repo.createSeedTray(tray(t.propertyId, id: 'other'));
    await repo.assignTrayCells(
      t,
      t.row(1),
      assignment(),
      packetPhotos: photos(),
    );
    await repo.setTrayTransplantDate(t, {TrayPosition(1, 1)}, '2027-01-20');
    final backup = await TrialBackupStore(storage, repo).export();
    final restored = LocalTrialRepository.open(
      storage,
      snapshot: BackupArchive.decode(backup)
          .records[LocalTrialRepository.storageKey],
    );
    final cells = await restored.watchTrayCells(t.propertyId, t.id).first;
    expect(cells[TrayPosition(1, 1)]!.transplantedOn, '2027-01-20');
    expect(cells[TrayPosition(1, 2)]!.transplantedOn, isNull);
    expect(
      await restored.watchRecords(t.propertyId, RecordKind.photo).first,
      hasLength(2),
    );
    await restored.deleteSeedTray(t.propertyId, t.id);
    final restarted = LocalTrialRepository.open(storage);
    expect(
      (await restarted.watchSeedTrays(t.propertyId).first).single.id,
      'other',
    );
    expect(await restarted.watchTrayCells(t.propertyId, t.id).first, isEmpty);
    expect(
      await restarted.watchRecords(t.propertyId, RecordKind.photo).first,
      isEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('native batch retains packet references and deletion clears tray cells and pending photo records', () async {
    final storage = await prefs(),
        db = FakeFirebaseFirestore(),
        repo = FirestoreOrchardRepository(db, storage),
        t = tray('property');
    await repo.createSeedTray(t);
    await repo.watchSeedTrays(t.propertyId).firstWhere((ts) => ts.isNotEmpty);
    await repo.assignTrayCells(
      t,
      t.row(1),
      assignment(),
      packetPhotos: photos(),
    );
    await repo
        .watchTrayCells(t.propertyId, t.id)
        .firstWhere((c) => c.length == 2);
    await repo.setTrayTransplantDate(t, {TrayPosition(1, 1)}, '2027-01-20');
    final cells = await repo
        .watchTrayCells(t.propertyId, t.id)
        .firstWhere((c) => c[TrayPosition(1, 1)]?.isTransplanted == true);
    expect(cells[TrayPosition(1, 2)]!.isTransplanted, isFalse);
    expect(cells[TrayPosition(1, 1)]!.packetBackId, 'back');
    await repo.deleteSeedTray(t.propertyId, t.id);
    expect(
      await repo.watchSeedTrays(t.propertyId).firstWhere((ts) => ts.isEmpty),
      isEmpty,
    );
    expect(
      await repo.watchRecords(t.propertyId, RecordKind.photo).first,
      isEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
