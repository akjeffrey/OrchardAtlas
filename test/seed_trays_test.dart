import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:orchard_atlas/domain/seed_trays.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/data/seed_tray_mapping.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 26);
  final taxon = starterTaxonomy.taxa
      .where((t) => t.rank == TaxonRank.species)
      .first
      .id;
  SeedTray tray(
    String property, {
    String id = 'tray',
    String name = 'Kitchen tray',
  }) => SeedTray(
    id: id,
    propertyId: property,
    name: name,
    rows: 3,
    columns: 4,
    createdAt: now,
  );
  TrayAssignment assignment({
    String label = 'Tomato',
    TrayContentKind kind = TrayContentKind.seed,
  }) => TrayAssignment(
    label: label,
    taxonId: taxon,
    kind: kind,
    assignedAt: now,
    symbol: PlantSymbol.flower,
  );
  Future<SharedPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('dimensions and row/column selection generate exactly the requested cells without duplicate intersections', () {
    final t = tray('p');
    expect(t.positions, hasLength(12));
    expect(t.row(2), hasLength(4));
    expect(t.column(3), hasLength(3));
    var selected = toggleTraySelection({}, t.row(2));
    selected = toggleTraySelection(selected, t.column(3));
    expect(selected, hasLength(6));
    selected = toggleTraySelection(selected, t.row(2));
    expect(selected, hasLength(2));
    expect(
      () => t.validateSelection({TrayPosition(4, 1)}),
      throwsArgumentError,
    );
    expect(
      () => SeedTray(
        id: 'x',
        propertyId: 'p',
        name: 'Tray',
        rows: 0,
        columns: 3,
        createdAt: now,
      ),
      throwsArgumentError,
    );
    expect(
      () => SeedTray(
        id: 'x',
        propertyId: 'p',
        name: 'Tray',
        rows: 24,
        columns: 24,
        createdAt: now,
      ),
      throwsArgumentError,
    );
  });
  test(
    'mapping retains cell content, position, icon and immutable tray identity',
    () {
      final t = tray('p');
      final p = TrayPosition(2, 3), a = assignment(kind: TrayContentKind.plant);
      final decoded = SeedTrayMapping.readCell(SeedTrayMapping.cell(t, p, a));
      expect(decoded.key, p);
      expect(decoded.value.kind, TrayContentKind.plant);
      expect(decoded.value.symbol, PlantSymbol.flower);
      expect(t.renamed('Windowsill').id, t.id);
      expect(t.renamed('Windowsill').rows, 3);
      expect(
        () => SeedTrayMapping.readCell({
          ...SeedTrayMapping.cell(t, p, a),
          'row': 1,
        }),
        throwsFormatException,
      );
    },
  );
  test('local tray assignments survive rename, restart, orchard isolation and Drive backup restore', () async {
    final storage = await prefs(), repo = LocalTrialRepository.open(storage);
    final t = tray(repo.place.id);
    await repo.createSeedTray(t);
    await repo.assignTrayCells(t, t.row(1), assignment());
    await repo.assignTrayCells(t, {
      TrayPosition(2, 2),
    }, assignment(label: 'Pepper', kind: TrayContentKind.plant));
    await repo.renameSeedTray(t.propertyId, t.id, 'Renamed tray');
    await repo.createSeedTray(
      tray(repo.place.id, id: 'other', name: 'Second tray'),
    );
    final orchard = await repo.createPlace(
      LocalTrialRepository.userId,
      'North orchard',
    );
    expect(await repo.watchSeedTrays(orchard.id).first, isEmpty);
    final backup = await TrialBackupStore(storage, repo).export();
    final restored = LocalTrialRepository.open(
      storage,
      snapshot: BackupArchive.decode(backup)
          .records[LocalTrialRepository.storageKey],
    );
    expect(
      (await restored.watchSeedTrays(t.propertyId).first).map((t) => t.name),
      containsAll(['Renamed tray', 'Second tray']),
    );
    final cells = await restored.watchTrayCells(t.propertyId, t.id).first;
    expect(cells, hasLength(5));
    expect(cells[TrayPosition(2, 2)]!.label, 'Pepper');
    await restored.clearTrayCells(t, {TrayPosition(1, 1)});
    expect(
      await restored.watchTrayCells(t.propertyId, t.id).first,
      hasLength(4),
    );
    expect(await restored.watchTrayCells(t.propertyId, 'other').first, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('Firestore cell writes update only selected positions and names without replacing unrelated cells', () async {
    final storage = await prefs(), db = FakeFirebaseFirestore();
    final repo = FirestoreOrchardRepository(db, storage);
    final t = tray('property');
    await repo.createSeedTray(t);
    await repo
        .watchSeedTrays(t.propertyId)
        .firstWhere((ts) => ts.any((v) => v.id == t.id));
    await repo.assignTrayCells(t, t.row(1), assignment());
    await repo
        .watchTrayCells(t.propertyId, t.id)
        .firstWhere((c) => c.length == 4);
    await repo.assignTrayCells(t, {
      TrayPosition(2, 2),
    }, assignment(label: 'Pepper'));
    final cells = await repo
        .watchTrayCells(t.propertyId, t.id)
        .firstWhere((c) => c.length == 5);
    expect(cells[TrayPosition(1, 1)]!.label, 'Tomato');
    expect(cells[TrayPosition(2, 2)]!.label, 'Pepper');
    await repo.renameSeedTray(t.propertyId, t.id, 'Tray B');
    final changed = await repo
        .watchSeedTrays(t.propertyId)
        .firstWhere((ts) => ts.single.name == 'Tray B');
    expect(changed.single.columns, 4);
    await repo.clearTrayCells(t, {TrayPosition(2, 2)});
    expect(
      await repo
          .watchTrayCells(t.propertyId, t.id)
          .firstWhere((c) => c.length == 4),
      hasLength(4),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
