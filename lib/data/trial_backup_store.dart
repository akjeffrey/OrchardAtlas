import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/backup.dart';
import '../domain/models.dart';
import 'local_trial_repository.dart';

class TrialBackupStore {
  TrialBackupStore(this.preferences, this.repository);
  final SharedPreferences preferences;
  final LocalTrialRepository repository;
  static const pendingKey = 'orchard-atlas-restore-pending-v1';
  static const recoveryKey = 'orchard-atlas-before-restore-v1';
  static bool included(String key) =>
      key == LocalTrialRepository.storageKey ||
      key == LocalTrialRepository.catalogKey ||
      key.startsWith('${LocalTrialRepository.storageKey}:orchard:') ||
      key == 'trial-selected:${LocalTrialRepository.userId}' ||
      key.startsWith('map-default:${LocalTrialRepository.userId}:') ||
      key == 'task-sort:${LocalTrialRepository.userId}';

  Map<String, String> records() => {
    for (final key in preferences.getKeys().where(included))
      key: preferences.getString(key)!,
  };
  Future<String> export() async {
    await repository.flushForBackup();
    final contents = BackupArchive(DateTime.now(), records()).encode();
    if (utf8.encode(contents).length > BackupArchive.maximumBytes) {
      throw StateError('Backup exceeds 20 MB');
    }
    return contents;
  }

  void validate(BackupArchive archive) {
    final records = archive.records;
    if (!records.containsKey(LocalTrialRepository.storageKey) ||
        records.keys.any((k) => !included(k))) {
      throw const FormatException('Invalid or unrelated backup records');
    }
    final main = LocalTrialRepository.open(
      preferences,
      snapshot: records[LocalTrialRepository.storageKey],
    );
    final ids = <String>{main.place.id};
    final catalog = jsonDecode(
      records[LocalTrialRepository.catalogKey] ?? '[]',
    );
    if (catalog is! List) {
      throw const FormatException('Invalid orchard catalog');
    }
    for (final entry in catalog) {
      final place = Place(
        id: entry['id'] as String,
        name: entry['name'] as String,
        ownerId: LocalTrialRepository.userId,
        createdAt: DateTime.parse(entry['createdAt'] as String),
      );
      if (!ids.add(place.id)) throw const FormatException('Duplicate orchard');
      final key = '${LocalTrialRepository.storageKey}:orchard:${place.id}';
      if (!records.containsKey(key)) {
        throw const FormatException('Missing orchard data');
      }
      LocalTrialRepository.open(
        preferences,
        orchard: place,
        snapshot: records[key],
      );
    }
    for (final key in records.keys.where(
      (k) => k.startsWith('${LocalTrialRepository.storageKey}:orchard:'),
    )) {
      if (!ids.contains(
        key.substring('${LocalTrialRepository.storageKey}:orchard:'.length),
      )) {
        throw const FormatException('Unknown orchard snapshot');
      }
    }
  }

  Future<void> restore(String contents) async {
    final archive = BackupArchive.decode(contents);
    validate(archive); // Parse all domain records before any mutation.
    await repository.flushForBackup();
    await _set(
      preferences,
      recoveryKey,
      BackupArchive(DateTime.now(), records()).encode(),
    );
    await _set(preferences, pendingKey, archive.encode());
    await finishRestore(preferences);
  }

  static Future<void> _set(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('Device storage rejected backup restore');
    }
  }

  static Future<void> finishRestore(SharedPreferences prefs) async {
    final raw = prefs.getString(pendingKey);
    if (raw == null) return;
    final archive = BackupArchive.decode(raw);
    TrialBackupStore(
      prefs,
      LocalTrialRepository.open(
        prefs,
        snapshot: archive.records[LocalTrialRepository.storageKey],
      ),
    ).validate(archive);
    for (final key in prefs.getKeys().where(included).toList()) {
      if (!archive.records.containsKey(key) && !await prefs.remove(key)) {
        throw StateError('Could not clear old record');
      }
    }
    for (final entry in archive.records.entries) {
      await _set(prefs, entry.key, entry.value);
    }
    if (!await prefs.remove(pendingKey)) {
      throw StateError('Could not finish restore');
    }
  }
}
