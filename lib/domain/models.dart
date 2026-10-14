enum TaxonRank { group, genus, species, cultivar }

enum ItemKind { managedPlant, foragingResource }

enum PermissionRole { owner, editor, viewer }

enum ActivityType {
  planting,
  bloom,
  pruning,
  fertilizing,
  spraying,
  pestsDisease,
  watering,
  harvest,
  removal,
  note,
  photo,
}

enum HarvestUnit { kg, g, lb, count }

String requiredText(String value, String field) {
  final result = value.trim();
  if (result.isEmpty || result.length > 500) {
    throw ArgumentError('$field must contain 1–500 characters');
  }
  return result;
}

class Coordinates {
  Coordinates(this.latitude, this.longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid latitude or longitude');
    }
  }
  final double latitude;
  final double longitude;
}

class Place {
  Place({
    required this.id,
    required String name,
    required this.ownerId,
    required this.createdAt,
  }) : name = requiredText(name, 'Property name');
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
}

class Taxon {
  const Taxon({
    required this.id,
    required this.name,
    required this.rank,
    this.parentId,
    this.scientificName,
  });
  final String id;
  final String name;
  final TaxonRank rank;
  final String? parentId;
  final String? scientificName;
}

abstract class TrackedItem {
  TrackedItem({
    required this.id,
    required this.propertyId,
    required String name,
    required this.taxonId,
    required this.location,
    required this.createdAt,
  }) : name = requiredText(name, 'Plant name');
  final String id;
  final String propertyId;
  final String name;
  final String taxonId;
  final Coordinates location;
  final DateTime createdAt;
  ItemKind get kind;
}

class ManagedPlant extends TrackedItem {
  ManagedPlant({
    required super.id,
    required super.propertyId,
    required super.name,
    required super.taxonId,
    required super.location,
    required super.createdAt,
  });
  @override
  ItemKind get kind => ItemKind.managedPlant;
  PlantTemplate get template => PlantTemplate(name: name, taxonId: taxonId);
}

class ForagingResource extends TrackedItem {
  ForagingResource({
    required super.id,
    required super.propertyId,
    required super.name,
    required super.taxonId,
    required super.location,
    required super.createdAt,
  });
  @override
  ItemKind get kind => ItemKind.foragingResource;
}

// A bulk-entry template deliberately contains no identity, location or history.
class PlantTemplate {
  const PlantTemplate({required this.name, required this.taxonId});
  final String name;
  final String taxonId;
}

class Harvest {
  Harvest(this.quantity, this.unit) {
    if (!quantity.isFinite ||
        quantity <= 0 ||
        quantity > 1000000000000 ||
        (unit == HarvestUnit.count && quantity != quantity.roundToDouble())) {
      throw ArgumentError(
        'Harvest must be positive; count must be a whole number',
      );
    }
  }
  final double quantity;
  final HarvestUnit unit;
  double get kilograms => switch (unit) {
    HarvestUnit.kg => quantity,
    HarvestUnit.g => quantity / 1000,
    HarvestUnit.lb => quantity * 0.45359237,
    HarvestUnit.count => 0,
  };
}

String calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime parseCalendarDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || calendarDate(parsed) != value) {
    throw ArgumentError('Activity date must be a valid YYYY-MM-DD date');
  }
  return parsed;
}

class PlantEvent {
  PlantEvent({
    required this.id,
    required this.propertyId,
    required this.itemId,
    required this.authorId,
    required this.type,
    required this.occurredAt,
    required this.activityDate,
    required this.recordedAt,
    this.notes = '',
    this.harvest,
  }) {
    parseCalendarDate(activityDate);
    if ((type == ActivityType.harvest) != (harvest != null)) {
      throw ArgumentError('Only harvest activities require harvest data');
    }
    if (notes.length > 10000) throw ArgumentError('Notes are too long');
  }
  final String id;
  final String propertyId;
  final String itemId;
  final String authorId;
  final ActivityType type;
  final DateTime occurredAt;
  final String activityDate;
  final DateTime recordedAt;
  final String notes;
  final Harvest? harvest;
}

class HarvestTotals {
  const HarvestTotals(this.kilograms, this.count);
  final double kilograms;
  final double count;
  factory HarvestTotals.forYear(Iterable<PlantEvent> events, int year) {
    var kg = 0.0;
    var count = 0.0;
    for (final event in events) {
      if (event.type != ActivityType.harvest ||
          parseCalendarDate(event.activityDate).year != year) {
        continue;
      }
      final harvest = event.harvest!;
      kg += harvest.kilograms;
      if (harvest.unit == HarvestUnit.count) count += harvest.quantity;
    }
    return HarvestTotals(kg, count);
  }
}

class OrchardTask {
  const OrchardTask({
    required this.id,
    required this.propertyId,
    required this.title,
    this.itemId,
    this.dueDate,
    this.completed = false,
  });
  final String id, propertyId, title;
  final String? itemId;
  final DateTime? dueDate;
  final bool completed;
}

class Photo {
  const Photo({
    required this.id,
    required this.propertyId,
    required this.itemId,
    required this.authorId,
    required this.storagePath,
    this.eventId,
  });
  final String id, propertyId, itemId, authorId, storagePath;
  final String? eventId;
}

class OrchardUser {
  const OrchardUser(this.id, {this.displayName});
  final String id;
  final String? displayName;
}

class Permission {
  const Permission(this.propertyId, this.userId, this.role);
  final String propertyId, userId;
  final PermissionRole role;
}
