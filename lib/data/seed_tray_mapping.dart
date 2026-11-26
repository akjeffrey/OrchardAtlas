import '../domain/models.dart';
import '../domain/seed_trays.dart';

class SeedTrayMapping {
  static Map<String,dynamic> tray(SeedTray t)=>{'schemaVersion':1,'id':t.id,'name':t.name,
    'rows':t.rows,'columns':t.columns,'createdAt':t.createdAt.toUtc().toIso8601String()};
  static SeedTray readTray(String property,Map<String,dynamic> d) {
    _version(d);
    return SeedTray(id:d['id'] as String,propertyId:property,name:d['name'] as String,
      rows:d['rows'] as int,columns:d['columns'] as int,createdAt:DateTime.parse(d['createdAt'] as String));
  }
  static Map<String,dynamic> cell(SeedTray t,TrayPosition p,TrayAssignment a)=>{
    'schemaVersion':1,'id':p.recordId(t.id),'trayId':t.id,'row':p.row,'column':p.column,
    'label':a.label,'taxonId':a.taxonId,'kind':a.kind.name,'assignedAt':a.assignedAt.toUtc().toIso8601String(),
    'symbol':a.symbol?.name,'customIconId':a.customIconId,
  };
  static MapEntry<TrayPosition,TrayAssignment> readCell(Map<String,dynamic> d) {
    _version(d);
    final p=TrayPosition(d['row'] as int,d['column'] as int);
    if(d['id']!=p.recordId(d['trayId'] as String))throw const FormatException('Cell identity does not match its position');
    return MapEntry(p,TrayAssignment(label:d['label'] as String,taxonId:d['taxonId'] as String,
      kind:TrayContentKind.values.byName(d['kind'] as String),assignedAt:DateTime.parse(d['assignedAt'] as String),
      symbol:d['symbol']==null?null:PlantSymbol.values.byName(d['symbol'] as String),customIconId:d['customIconId'] as String?));
  }
  static void _version(Map<String,dynamic> d) {if(d['schemaVersion']!=1)throw const FormatException('Unsupported seed tray data');}
}
