import 'landscape.dart';
import 'models.dart';
import 'work.dart';

/// A display projection only. Conversions never move records or rewrite IDs.
class PlantEntry {
  const PlantEntry(this.plant, {this.cropRecord = false});
  final ManagedPlant plant;
  final bool cropRecord;
}

List<PlantEntry> plantEntries(
  List<ManagedPlant> plants,
  List<CropPlanting> crops,
  List<OrchardSection> sections,
) => [
  for (final p in plants) PlantEntry(p),
  for (final c in crops)
    PlantEntry(
      ManagedPlant(
        id: c.id,
        propertyId: c.propertyId,
        name: c.label,
        taxonId: c.taxonId,
        location: sectionCenter(
          sections.firstWhere((s) => s.id == c.sectionId),
        ),
        createdAt: c.createdAt,
        sectionId: c.sectionId,
        plantedOn: c.plantedOn,
        notes: c.notes,
        lifeCycle: c.lifeCycle,
        season: c.season,
        status: c.status == CropStatus.growing
            ? ItemStatus.active
            : ItemStatus.archived,
      ),
      cropRecord: true,
    ),
];
