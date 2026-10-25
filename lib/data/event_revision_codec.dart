import '../domain/models.dart';
import 'landscape_mapping.dart';

class EventRevisionCodec {
  static PlantEvent read(String orchard, Map<String, dynamic> r) {
    final e = Map<String, dynamic>.from(r['event'] as Map);
    return PlantEvent(
      id: r['eventId'] as String,
      propertyId: orchard,
      itemId: r['itemId'] as String,
      authorId: e['authorId'] as String,
      type: ActivityType.values.byName(e['type'] as String),
      occurredAt: LandscapeMapping.readTime(e['occurredAt'] as Object),
      activityDate: e['activityDate'] as String,
      recordedAt: LandscapeMapping.readTime(e['recordedAt'] as Object),
      notes: e['notes'] as String,
      taskId: e['taskId'] as String?,
      harvest: e['harvest'] == null
          ? null
          : Harvest(
              (e['harvest']['quantity'] as num).toDouble(),
              HarvestUnit.values.byName(e['harvest']['unit'] as String),
            ),
    );
  }
}
