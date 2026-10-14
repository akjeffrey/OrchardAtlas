import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/data/firestore_mapping.dart';
import 'package:orchard_atlas/domain/models.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  final plant = ManagedPlant(
    id: 'plant',
    propertyId: 'place',
    name: 'Apple',
    taxonId: 'species',
    location: Coordinates(51.234, -0.124),
    createdAt: now,
  );
  test('plant mapping round-trips native location and timestamp without leaking SDK into domain', () {
    final map = FirestoreMapping.plantToMap(plant);
    expect(map['location'], isA<GeoPoint>());
    expect(map['createdAt'], isA<Timestamp>());
    final read = FirestoreMapping.plantFromMap('place', 'plant', map);
    expect(read.name, plant.name);
    expect(read.id, plant.id);
    expect(read.propertyId, plant.propertyId);
    expect(read.taxonId, plant.taxonId);
    expect(read.location.longitude, plant.location.longitude);
    expect(read.createdAt, now);
  });
  test('place and all activity types round trip', () {
    final place = Place(
      id: 'place',
      name: 'Home',
      ownerId: 'user',
      createdAt: now,
    );
    expect(
      FirestoreMapping.placeFromMap(
        place.id,
        FirestoreMapping.placeToMap(place),
      ).ownerId,
      'user',
    );
    for (final type in ActivityType.values) {
      final event = PlantEvent(
        id: 'e',
        propertyId: 'place',
        itemId: 'plant',
        authorId: 'user',
        type: type,
        occurredAt: now,
        activityDate: '2026-10-14',
        recordedAt: now,
        notes: 'Field note',
        harvest: type == ActivityType.harvest
            ? Harvest(2, HarvestUnit.lb)
            : null,
      );
      final read = FirestoreMapping.eventFromMap(
        'place',
        'plant',
        'e',
        FirestoreMapping.eventToMap(event),
      );
      expect(read.type, type);
      expect(read.activityDate, event.activityDate);
      expect(read.notes, event.notes);
      expect(read.occurredAt, now);
      expect(read.harvest?.unit, event.harvest?.unit);
      expect(read.harvest?.quantity, event.harvest?.quantity);
    }
  });
  test(
    'unsupported versions, kinds and malformed native fields fail explicitly',
    () {
      final map = FirestoreMapping.plantToMap(plant);
      expect(
        () => FirestoreMapping.plantFromMap('p', 'i', {
          ...map,
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => FirestoreMapping.plantFromMap('p', 'i', {
          ...map,
          'kind': 'unknown',
        }),
        throwsFormatException,
      );
      expect(
        () => FirestoreMapping.plantFromMap('p', 'i', {
          ...map,
          'location': '51,1',
        }),
        throwsA(isA<TypeError>()),
      );
    },
  );
}
