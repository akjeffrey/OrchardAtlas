import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../data/backup_documents.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? message;
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<bool> confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) {
    final service = ref.watch(backupServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Google Drive backup', style: TextStyle(fontSize: 22)),
          const Text(
            'Choose Google Drive in the Android file picker. The backup contains all orchards on this phone, including locations, notes, activities, tasks and settings. Choose a private folder.',
          ),
          const SizedBox(height: 12),
          Text(
            service.connected
                ? 'Backup file selected · saved changes are backed up at most once a minute while the app is running.'
                : 'No backup file selected. Edits save locally. Device data is lost on uninstall unless you create a backup.',
          ),
          Text(
            service.lastSaved == null
                ? 'No successful backup yet.'
                : 'Last successful write: ${service.lastSaved}. Check the Drive app has finished uploading before uninstalling.',
          ),
          if (service.busy) const LinearProgressIndicator(),
          if (service.error != null)
            Text('Backup needs attention: ${service.error}'),
          FilledButton.icon(
            onPressed: service.busy ? null : () => run(service.connect),
            icon: const Icon(Icons.cloud_upload),
            label: Text(
              service.connected
                  ? 'Choose a new backup file'
                  : 'Set up Drive backup',
            ),
          ),
          OutlinedButton(
            onPressed: service.busy || !service.connected
                ? null
                : () => run(service.save),
            child: const Text('Back up now'),
          ),
          OutlinedButton(
            onPressed: service.busy
                ? null
                : () => run(() async {
                    if (!await confirm(
                      'Replace phone data from backup?',
                      'This replaces all local orchard records with the selected file. A local recovery copy is kept until uninstall. Export a backup first to keep your current data.',
                    )) {
                      return;
                    }
                    if (await service.restore()) {
                      if (mounted) {
                        setState(
                          () => message = 'Backup restored. All orchards are available in the orchard selector. Set up a backup file to resume automatic backups.',
                        );
                      }
                    }
                  }),
            child: const Text('Restore from Drive or a backup file'),
          ),
          if (service.canUndoRestore)
            OutlinedButton(
              onPressed: service.busy
                  ? null
                  : () => run(() async {
                      if (!await confirm(
                        'Undo the last restore?',
                        'Replace phone data with the local recovery copy saved immediately before the last restore?',
                      )) {
                        return;
                      }
                      await service.undoRestore();
                      if (mounted) {
                        setState(
                          () => message = 'Previous phone data restored. Set up a backup file to resume automatic backups.',
                        );
                      }
                    }),
              child: const Text('Undo last restore'),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Retain backup when preparing to uninstall'),
            subtitle: const Text(
              'On by default. Android uninstall cannot show an app prompt; external Drive files remain until you explicitly delete them.',
            ),
            value: service.retain,
            onChanged: service.busy
                ? null
                : (v) => run(() => service.setRetain(v)),
          ),
          OutlinedButton(
            onPressed: service.busy
                ? null
                : () => run(() async {
                    if (service.retain) {
                      if (!service.connected) {
                        setState(
                          () => message = 'Create a Drive backup first, then prepare to uninstall.',
                        );
                        return;
                      }
                      await service.save();
                      if (mounted) {
                        setState(
                          () => message = 'Backup retained. Check Drive has uploaded it before uninstalling from Android settings. After reinstall, use Restore from Drive.',
                        );
                      }
                    } else if (await confirm(
                      'Delete the selected backup?',
                      'This permanently removes the selected backup file. Other copies remain. Phone records are kept until Android uninstalls the app.',
                    )) {
                      await service.deleteBackup();
                      if (mounted) {
                        setState(
                          () => message = 'Selected backup deleted. Uninstalling now also removes the local app data.',
                        );
                      }
                    }
                  }),
            child: const Text('Prepare to uninstall'),
          ),
          if (message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
          const Divider(),
          FutureBuilder<String>(
            future: AndroidBackupDocuments.appVersion(),
            builder: (c, s) => Text('OrchardAtlas ${s.data ?? ''}'),
          ),
          const Text(
            'Updates with the same application ID and signing key keep local data. Backups stay in your selected folder independently of app installation.',
          ),
        ],
      ),
    );
  }
}
