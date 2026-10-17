import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/backup.dart';
import '../data/trial_backup_store.dart';

class BackupService extends ChangeNotifier {
  BackupService(this.store, this.documents, {this.onRestored}) {
    _subscription = store.repository.backupChanges.listen((_) => schedule());
    if (connected) schedule();
  }
  final void Function()? onRestored;
  final TrialBackupStore store;
  final BackupDocuments documents;
  SharedPreferences get preferences => store.preferences;
  static const documentKey = 'drive-backup-document-v1';
  static const retainKey = 'drive-backup-retain-v1';
  static const savedKey = 'drive-backup-saved-v1';
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  bool busy = false, _disposed = false, _dirty = false, paused = false;
  String? error;
  bool get connected => preferences.getString(documentKey) != null;
  bool get canUndoRestore =>
      preferences.containsKey(TrialBackupStore.recoveryKey);
  bool get retain => preferences.getBool(retainKey) ?? true;
  String? get lastSaved => preferences.getString(savedKey);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setRetain(bool value) async {
    if (!await preferences.setBool(retainKey, value)) {
      throw StateError('Could not save retention choice');
    }
    changed();
  }

  void schedule() {
    if (!connected || paused || _disposed) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () async {
      try {
        await save();
      } catch (_) {
        /* Exposed in status, retry on next change/restart. */
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) throw StateError('Wait for the current backup operation');
    busy = true;
    error = null;
    changed();
    try {
      await action();
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> connect() => _run(() async {
    final document = await documents.create();
    if (document == null) return;
    final contents = await store.export();
    await documents.write(document, contents);
    if (!await preferences.setString(documentKey, document)) {
      throw StateError('Could not remember backup file');
    }
    await preferences.setString(savedKey, DateTime.now().toIso8601String());
    schedule();
  });
  Future<void> save() async {
    if (busy) {
      _dirty = true;
      return;
    }
    if (paused || !connected) return;
    await _run(() async {
      do {
        _dirty = false;
        await documents.write(
          preferences.getString(documentKey)!,
          await store.export(),
        );
        if (!await preferences.setString(
          savedKey,
          DateTime.now().toIso8601String(),
        )) {
          throw StateError('Could not save backup status');
        }
      } while (_dirty && !_disposed && !paused);
    });
  }

  Future<bool> restore() async {
    var restored = false;
    _timer?.cancel();
    paused = true;
    try {
      await _run(() async {
        final document = await documents.select();
        if (document == null) return;
        final contents = await documents.read(document);
        await store.restore(contents);
        // A restored file is not an automatic write target until explicitly selected as a new backup.
        await preferences.remove(documentKey);
        restored = true;
      });
    } finally {
      paused = false;
    }
    if (restored) onRestored?.call();
    return restored;
  }

  Future<void> undoRestore() async {
    _timer?.cancel();
    paused = true;
    try {
      await _run(() async {
        final raw = preferences.getString(TrialBackupStore.recoveryKey);
        if (raw == null) throw StateError('No recovery copy available');
        await store.restore(raw);
        await preferences.remove(documentKey);
      });
    } finally {
      paused = false;
    }
    onRestored?.call();
  }

  Future<void> deleteBackup() => _run(() async {
    final document = preferences.getString(documentKey);
    if (document != null) await documents.delete(document);
    if (!await preferences.remove(documentKey)) {
      throw StateError('Could not disconnect backup');
    }
    await preferences.remove(savedKey);
    _timer?.cancel();
  });
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _subscription.cancel();
    super.dispose();
  }
}
