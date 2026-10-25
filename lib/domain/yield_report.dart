import 'models.dart';
import 'landscape.dart';
import 'taxonomy.dart';

class YieldRow {
  const YieldRow(
    this.date,
    this.label,
    this.taxonId,
    this.harvest,
    this.sourceId,
  );
  final String date, label, taxonId, sourceId;
  final Harvest harvest;
}

List<YieldRow> yieldRows(
  List<PlantEvent> events,
  List<ManagedPlant> plants,
  List<CropHarvest> harvests,
  List<CropPlanting> crops,
) {
  final byPlant = {for (final p in plants) p.id: p},
      byCrop = {for (final c in crops) c.id: c};
  return [
    for (final e in events.where(
      (e) => e.harvest != null && byPlant.containsKey(e.itemId),
    ))
      YieldRow(
        e.activityDate,
        byPlant[e.itemId]!.name,
        byPlant[e.itemId]!.taxonId,
        e.harvest!,
        e.id,
      ),
    for (final h in harvests.where((h) => byCrop.containsKey(h.cropId)))
      YieldRow(
        h.activityDate,
        byCrop[h.cropId]!.label,
        byCrop[h.cropId]!.taxonId,
        h.harvest,
        h.id,
      ),
  ]..sort((a, b) => b.date.compareTo(a.date));
}

Map<String, HarvestTotals> summarizeYield(
  List<YieldRow> rows,
  Taxonomy taxonomy, {
  required int year,
  String? taxonId,
  bool monthly = false,
}) {
  final scope = taxonId == null ? null : taxonomy.descendants(taxonId);
  final result = <String, HarvestTotals>{};
  for (final r in rows.where(
    (r) =>
        parseCalendarDate(r.date).year == year &&
        (scope == null || scope.contains(r.taxonId)),
  )) {
    final key = monthly ? r.date.substring(0, 7) : r.label;
    final old = result[key] ?? const HarvestTotals(0, 0);
    result[key] = HarvestTotals(
      old.kilograms + r.harvest.kilograms,
      old.count +
          (r.harvest.unit == HarvestUnit.count ? r.harvest.quantity : 0),
    );
  }
  return result;
}

String yieldCsv(Iterable<YieldRow> rows) {
  String cell(String s) => '"${s.replaceAll('"', '""')}"';
  return 'Date,Plant,Taxon,Quantity,Unit,Source ID\r\n${rows.map((r) => [r.date, r.label, r.taxonId, r.harvest.quantity.toString(), r.harvest.unit.name, r.sourceId].map(cell).join(',')).join('\r\n')}';
}
