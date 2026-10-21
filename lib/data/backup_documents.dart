import 'package:flutter/services.dart';

import '../domain/backup.dart';

class AndroidBackupDocuments implements BackupDocuments {
  static const channel = MethodChannel('orchard_atlas/backup');
  @override
  Future<String?> create() => channel.invokeMethod<String>('create');
  @override
  Future<String?> select() => channel.invokeMethod<String>('select');
  @override
  Future<void> retainForBackup(String document) =>
      channel.invokeMethod<void>('retainForBackup', {'uri': document});
  @override
  Future<String> read(String document) async =>
      (await channel.invokeMethod<String>('read', {'uri': document}))!;
  @override
  Future<void> write(String document, String contents) => channel
      .invokeMethod<void>('write', {'uri': document, 'contents': contents});
  @override
  Future<void> delete(String document) =>
      channel.invokeMethod<void>('delete', {'uri': document});
  static Future<String> appVersion() async {
    try {
      return await channel.invokeMethod<String>('version') ??
          const String.fromEnvironment(
            'APP_VERSION',
            defaultValue: 'Development build',
          );
    } on MissingPluginException {
      return const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'Development build',
      );
    }
  }
}
