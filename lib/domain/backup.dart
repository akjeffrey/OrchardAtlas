import 'dart:convert';

class BackupArchive {
  BackupArchive(this.createdAt, Map<String, String> records)
    : records = Map.unmodifiable(records);
  final DateTime createdAt;
  final Map<String, String> records;
  static const maximumBytes = 20 * 1024 * 1024;
  String encode() => jsonEncode({
    'format': 'OrchardAtlasBackup',
    'version': 1,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'records': records,
  });
  static BackupArchive decode(String contents) {
    if (utf8.encode(contents).length > maximumBytes) {
      throw const FormatException('Backup exceeds 20 MB');
    }
    final data = jsonDecode(contents);
    if (data is! Map ||
        data['format'] != 'OrchardAtlasBackup' ||
        data['version'] != 1 ||
        data['records'] is! Map ||
        data['createdAt'] is! String) {
      throw const FormatException('Not a supported OrchardAtlas backup');
    }
    final records = <String, String>{};
    for (final entry in (data['records'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid backup records');
      }
      records[entry.key as String] = entry.value as String;
    }
    return BackupArchive(DateTime.parse(data['createdAt'] as String), records);
  }
}

abstract interface class BackupDocuments {
  Future<String?> create();
  Future<String?> select();

  /// Verify persistent read/write access without overwriting the selected file.
  Future<void> retainForBackup(String document);
  Future<String> read(String document);
  Future<void> write(String document, String contents);
  Future<void> delete(String document);
}
