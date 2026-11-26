import 'models.dart';

enum TrayContentKind { seed, plant }

class TrayPosition {
  TrayPosition(this.row, this.column) {
    if (row < 1 || column < 1) throw ArgumentError('Cell positions start at 1');
  }
  final int row, column;
  String get key => '$row:$column';
  String recordId(String trayId) => '${trayId}_${row}_$column';
  @override
  bool operator ==(Object other) => other is TrayPosition && row == other.row && column == other.column;
  @override
  int get hashCode => Object.hash(row, column);
}

class SeedTray {
  SeedTray({required this.id, required this.propertyId, required String name,
    required this.rows, required this.columns, required this.createdAt})
      : name = requiredText(name, 'Tray name') {
    if (rows < 1 || rows > maxDimension || columns < 1 || columns > maxDimension || rows * columns > maxCells) {
      throw ArgumentError('Use 1–24 rows and columns, with at most 400 cells');
    }
  }
  static const maxDimension = 24, maxCells = 400;
  final String id, propertyId, name;
  final int rows, columns;
  final DateTime createdAt;
  int get capacity => rows * columns;
  bool contains(TrayPosition p) => p.row <= rows && p.column <= columns;
  Set<TrayPosition> get positions => {for(var r=1;r<=rows;r++)for(var c=1;c<=columns;c++)TrayPosition(r,c)};
  Set<TrayPosition> row(int r) { if(r<1 || r>rows)throw ArgumentError('Invalid row');return {for(var c=1;c<=columns;c++)TrayPosition(r,c)}; }
  Set<TrayPosition> column(int c) { if(c<1 || c>columns)throw ArgumentError('Invalid column');return {for(var r=1;r<=rows;r++)TrayPosition(r,c)}; }
  SeedTray renamed(String value)=>SeedTray(id:id,propertyId:propertyId,name:value,rows:rows,columns:columns,createdAt:createdAt);
  void validateSelection(Set<TrayPosition> selected) {
    if(selected.isEmpty || selected.any((p)=>!contains(p)))throw ArgumentError('Select cells within this tray');
  }
}

Set<TrayPosition> toggleTraySelection(Set<TrayPosition> selected,Set<TrayPosition> group) =>
  selected.containsAll(group) ? (Set<TrayPosition>.of(selected)..removeAll(group)) : {...selected,...group};

class TrayAssignment {
  TrayAssignment({required String label, required this.taxonId, required this.kind,
    required this.assignedAt, this.symbol, this.customIconId}) : label=requiredText(label,'Seed / plant name');
  final String label, taxonId;
  final TrayContentKind kind;
  final DateTime assignedAt;
  /// Null means resolve the current inherited classification icon.
  final PlantSymbol? symbol;
  final String? customIconId;
}

abstract interface class SeedTrayRepository {
  Stream<List<SeedTray>> watchSeedTrays(String propertyId);
  Stream<Map<TrayPosition,TrayAssignment>> watchTrayCells(String propertyId,String trayId);
  Future<void> createSeedTray(SeedTray tray);
  Future<void> renameSeedTray(String propertyId,String trayId,String name);
  Future<void> assignTrayCells(SeedTray tray,Set<TrayPosition> positions,TrayAssignment assignment);
  Future<void> clearTrayCells(SeedTray tray,Set<TrayPosition> positions);
}
