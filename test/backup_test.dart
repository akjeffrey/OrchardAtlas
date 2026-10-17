import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/backup_service.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';

class _Documents implements BackupDocuments {
  String? selected = 'content://drive/backup';
  final files = <String, String>{};
  bool failWrite = false;
  int writes = 0;
  @override
  Future<String?> create() async => selected;
  @override
  Future<String?> select() async => selected;
  @override
  Future<String> read(String document) async => files[document]!;
  @override
  Future<void> write(String document, String contents) async {
    if (failWrite) throw StateError('Offline');
    writes++;
    files[document] = contents;
  }

  @override
  Future<void> delete(String document) async {
    files.remove(document);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LocalTrialRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = LocalTrialRepository.open(prefs);
  });
  final taxon = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Honeycrisp');
  test('all orchard records restore while secrets and document grants stay excluded', () async {
    final second = await repo.createPlace(LocalTrialRepository.userId, 'North');
    final commands = OrchardCommands(repo, starterTaxonomy);
    for (final place in [repo.place, second]) {
      commands.addPlant(
        place: place,
        name: place.name,
        taxonId: taxon.id,
        location: Coordinates(51, 1),
        plantingDate: DateTime(2020),
        authorId: LocalTrialRepository.userId,
      );
    }
    await prefs.setString('auth-token', 'private');
    await prefs.setString(BackupService.documentKey, 'content://old');
    await prefs.setString(
      'map-default:${LocalTrialRepository.userId}:${second.id}',
      '{"latitude":51}',
    );
    final store = TrialBackupStore(prefs, repo), saved = await store.export();
    final archive = BackupArchive.decode(saved);
    expect(archive.records.containsKey('auth-token'), isFalse);
    expect(archive.records.containsKey(BackupService.documentKey), isFalse);
    final p = repo.plants.single;
    repo.updatePlant(p.copyWith(name: 'Changed'));
    await store.restore(saved);
    final restarted = LocalTrialRepository.open(prefs);
    expect(restarted.plants.single.name, 'Home Orchard');
    expect(restarted.events.single.activityDate, '2020-01-01');
    expect(
      (await restarted.watchPlants(second.id).first).value.single.name,
      'North',
    );
    expect(prefs.getString('auth-token'), 'private');
    expect(prefs.getString(TrialBackupStore.pendingKey), isNull);
    expect(prefs.getString(TrialBackupStore.recoveryKey), isNotNull);
  });
  test('invalid later orchard does not mutate any existing data', () async {
    await repo.flushForBackup();
    final store = TrialBackupStore(prefs, repo);
    final before = await store.export();
    final entries = Map<String, String>.of(
      BackupArchive.decode(before).records,
    );
    entries[LocalTrialRepository.catalogKey] = jsonEncode([
      {'id': 'bad', 'name': 'Bad', 'createdAt': '2026-01-01T00:00:00Z'},
    ]);
    entries['${LocalTrialRepository.storageKey}:orchard:bad'] =
        '{"createdAt":"broken","plants":[{}]}';
    await expectLater(
      store.restore(BackupArchive(DateTime.now(), entries).encode()),
      throwsA(anything),
    );
    expect(store.records(), BackupArchive.decode(before).records);
    expect(prefs.getString(TrialBackupStore.pendingKey), isNull);
    entries['auth-token'] = 'malicious';
    await expectLater(
      store.restore(BackupArchive(DateTime.now(), entries).encode()),
      throwsFormatException,
    );
  });
  test(
    'restore journal completes on next startup after interruption',
    () async {
      await repo.flushForBackup();
      final store = TrialBackupStore(prefs, repo);
      final saved = await store.export();
      await prefs.setString(TrialBackupStore.pendingKey, saved);
      await prefs.remove(LocalTrialRepository.storageKey);
      await TrialBackupStore.finishRestore(prefs);
      expect(LocalTrialRepository.open(prefs).place.name, 'Home Orchard');
      expect(prefs.getString(TrialBackupStore.pendingKey), isNull);
    },
  );
  test('retention defaults on; cancelled picker and failed writes never report success', () async {
    final docs = _Documents()..selected = null;
    final service = BackupService(TrialBackupStore(prefs, repo), docs);
    addTearDown(service.dispose);
    expect(service.retain, isTrue);
    await service.connect();
    expect(service.connected, isFalse);
    docs.selected = 'content://drive/file';
    docs.failWrite = true;
    await expectLater(service.connect(), throwsStateError);
    expect(service.lastSaved, isNull);
    expect(service.connected, isFalse);
    docs.failWrite = false;
    await service.connect();
    expect(service.connected, isTrue);
    await service.setRetain(false);
    expect(service.retain, isFalse);
    expect(
      docs.files,
      isNotEmpty,
    ); // Changing preference alone never deletes a file.
    await service.deleteBackup();
    expect(docs.files, isEmpty);
    expect(service.connected, isFalse);
  });
  test('automatic backup captures subsequent writes and explicit retry recovers offline errors', () async {
    final docs = _Documents();
    final service = BackupService(TrialBackupStore(prefs, repo), docs);
    addTearDown(service.dispose);
    await service.connect();
    OrchardCommands(repo, starterTaxonomy).addPlant(
      place: repo.place,
      name: 'Later',
      taxonId: taxon.id,
      location: Coordinates(51, 1),
    );
    await repo.flushForBackup();
    docs.failWrite = true;
    await expectLater(service.save(), throwsStateError);
    expect(service.error, isNotNull);
    docs.failWrite = false;
    await service.save();
    expect(service.error, isNull);
    final archive = BackupArchive.decode(docs.files.values.single);
    expect(
      jsonDecode(
        archive.records[LocalTrialRepository.storageKey]!,
      )['plants'].single['name'],
      'Later',
    );
  });
  test('unknown backup formats, non-string records and oversize inputs are rejected', () {
    for (final input in [
      '{}',
      '{"format":"OrchardAtlasBackup","version":2,"createdAt":"2026-01-01","records":{}}',
      '{"format":"OrchardAtlasBackup","version":1,"createdAt":"2026-01-01","records":{"key":3}}',
    ]) {
      expect(() => BackupArchive.decode(input), throwsFormatException);
    }
    expect(
      () => BackupArchive.decode(' ' * (BackupArchive.maximumBytes + 1)),
      throwsFormatException,
    );
  });
}
