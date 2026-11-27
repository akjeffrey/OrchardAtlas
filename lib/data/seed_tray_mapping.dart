import 'dart:convert';

import '../domain/models.dart';
import '../domain/seed_trays.dart';

class SeedTrayMapping {
  static Map<String, dynamic> tray(SeedTray t) => {
    'schemaVersion': 1,
    'id': t.id,
    'name': t.name,
    'rows': t.rows,
    'columns': t.columns,
    'createdAt': t.createdAt.toUtc().toIso8601String(),
    if (t.deleting) 'deleting': true,
  };
  static SeedTray readTray(String property, Map<String, dynamic> d) {
    _version(d);
    return SeedTray(
      id: d['id'] as String,
      propertyId: property,
      name: d['name'] as String,
      rows: d['rows'] as int,
      columns: d['columns'] as int,
      createdAt: DateTime.parse(d['createdAt'] as String),
      deleting: d['deleting'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> cell(
    SeedTray t,
    TrayPosition p,
    TrayAssignment a,
  ) => {
    'schemaVersion': 1,
    'id': p.recordId(t.id),
    'trayId': t.id,
    'row': p.row,
    'column': p.column,
    'label': a.label,
    'taxonId': a.taxonId,
    'kind': a.kind.name,
    'assignedAt': a.assignedAt.toUtc().toIso8601String(),
    'symbol': a.symbol?.name,
    'customIconId': a.customIconId,
    'plantedOn': a.plantedOn,
    'transplantAfterDays': a.transplantAfterDays,
    'transplantedOn': a.transplantedOn,
    'packetFrontId': a.packetFrontId,
    'packetBackId': a.packetBackId,
    if (a.usePacketFrontIcon) 'usePacketFrontIcon': true,
  };
  static MapEntry<TrayPosition, TrayAssignment> readCell(
    Map<String, dynamic> d,
  ) {
    _version(d);
    final p = TrayPosition(d['row'] as int, d['column'] as int);
    if (d['id'] != p.recordId(d['trayId'] as String)) {
      throw const FormatException('Cell identity does not match its position');
    }
    return MapEntry(
      p,
      TrayAssignment(
        label: d['label'] as String,
        taxonId: d['taxonId'] as String,
        kind: TrayContentKind.values.byName(d['kind'] as String),
        assignedAt: DateTime.parse(d['assignedAt'] as String),
        symbol: d['symbol'] == null
            ? null
            : PlantSymbol.values.byName(d['symbol'] as String),
        customIconId: d['customIconId'] as String?,
        plantedOn: d['plantedOn'] as String?,
        transplantAfterDays: d['transplantAfterDays'] as int?,
        transplantedOn: d['transplantedOn'] as String?,
        packetFrontId: d['packetFrontId'] as String?,
        packetBackId: d['packetBackId'] as String?,
        usePacketFrontIcon: d['usePacketFrontIcon'] as bool? ?? false,
      ),
    );
  }

  static Map<String, dynamic> packetPhoto(
    SeedTray tray,
    SeedPacketPhoto p, {
    required bool connected,
  }) => {
    'id': p.id,
    'itemId': tray.id,
    'authorId': p.authorId,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'storagePath':
        'properties/${tray.propertyId}/items/${tray.id}/photos/${p.id}.jpg',
    'image': base64Encode(p.image),
    'thumbnail': base64Encode(p.thumbnail),
    'state': connected ? 'pending' : 'local',
    'error': null,
  };

  static void _version(Map<String, dynamic> d) {
    if (d['schemaVersion'] != 1) {
      throw const FormatException('Unsupported seed tray data');
    }
  }
}
