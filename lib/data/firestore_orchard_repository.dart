import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'firestore_mapping.dart';

class FirestoreOrchardRepository implements OrchardRepository {
  FirestoreOrchardRepository(this.firestore, this.preferences);
  final FirebaseFirestore firestore;
  final SharedPreferences preferences;
  final _failures = StreamController<WriteFailure>.broadcast();
  @override
  Stream<WriteFailure> get writeFailures => _failures.stream;
  CollectionReference<Map<String, dynamic>> _items(String propertyId) =>
      firestore.collection('properties').doc(propertyId).collection('items');

  void _observe(String id, Future<void> acknowledgement) {
    unawaited(
      acknowledgement.catchError((Object error) {
        final code = error is FirebaseException ? error.code : 'write-failed';
        _failures.add(
          WriteFailure(
            id,
            'Sync rejected ($code). This record may have been rolled back. Restore access and enter it again.',
          ),
        );
      }),
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _cachedProperty(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      final cached = await reference.get(
        const GetOptions(source: Source.cache),
      );
      if (cached.exists) return cached;
    } on FirebaseException catch (error) {
      // A cache miss needs the server. Other errors must remain visible.
      if (error.code != 'unavailable') rethrow;
    }
    return reference.get(const GetOptions(source: Source.server));
  }

  @override
  Future<Place> openDefaultPlace(String userId) async {
    final key = 'default-place:$userId';
    final knownId = preferences.getString(key);
    if (knownId != null) {
      final reference = firestore.collection('properties').doc(knownId);
      final doc = await _cachedProperty(reference);
      if (!doc.exists) {
        throw StateError('Property unavailable. Reconnect to restore access.');
      }
      final place = FirestoreMapping.placeFromMap(doc.id, doc.data()!);
      if (place.ownerId != userId) {
        throw StateError('Property belongs to another account');
      }
      return place;
    }
    // Server lookup prevents a cache miss from creating duplicate default places.
    final existing = await firestore
        .collection('properties')
        .where('ownerId', isEqualTo: userId)
        .get(const GetOptions(source: Source.server));
    final docs = existing.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
    final Place place;
    if (docs.isNotEmpty) {
      place = FirestoreMapping.placeFromMap(docs.first.id, docs.first.data());
    } else {
      place = Place(
        id: const Uuid().v4(),
        name: 'My orchard',
        ownerId: userId,
        createdAt: DateTime.now().toUtc(),
      );
      _observe(
        place.id,
        firestore
            .collection('properties')
            .doc(place.id)
            .set(FirestoreMapping.placeToMap(place)),
      );
    }
    await preferences.setString(key, place.id);
    return place;
  }

  @override
  Stream<RepositorySnapshot<List<ManagedPlant>>> watchPlants(
    String propertyId,
  ) => _items(propertyId).snapshots(includeMetadataChanges: true).map((s) {
    final plants =
        s.docs
            .map(
              (d) => FirestoreMapping.plantFromMap(propertyId, d.id, d.data()),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return RepositorySnapshot(
      plants,
      isFromCache: s.metadata.isFromCache,
      hasPendingWrites: s.metadata.hasPendingWrites,
    );
  });
  @override
  Stream<RepositorySnapshot<List<PlantEvent>>> watchEvents(
    String propertyId,
    String itemId,
  ) => _items(propertyId)
      .doc(itemId)
      .collection('events')
      .snapshots(includeMetadataChanges: true)
      .map((s) {
        final events =
            s.docs
                .map(
                  (d) => FirestoreMapping.eventFromMap(
                    propertyId,
                    itemId,
                    d.id,
                    d.data(),
                  ),
                )
                .toList()
              ..sort((a, b) {
                final date = b.activityDate.compareTo(a.activityDate);
                return date != 0 ? date : b.recordedAt.compareTo(a.recordedAt);
              });
        return RepositorySnapshot(
          events,
          isFromCache: s.metadata.isFromCache,
          hasPendingWrites: s.metadata.hasPendingWrites,
        );
      });
  @override
  void savePlant(ManagedPlant plant, {PlantEvent? plantingEvent}) {
    final batch = firestore.batch();
    final item = _items(plant.propertyId).doc(plant.id);
    batch.set(item, FirestoreMapping.plantToMap(plant));
    if (plantingEvent != null) {
      if (plantingEvent.itemId != plant.id ||
          plantingEvent.propertyId != plant.propertyId) {
        throw ArgumentError('Planting activity must belong to this plant');
      }
      batch.set(
        item.collection('events').doc(plantingEvent.id),
        FirestoreMapping.eventToMap(plantingEvent),
      );
    }
    _observe(plant.id, batch.commit());
  }

  @override
  Stream<List<Taxon>> watchTaxa(String propertyId) => firestore
      .collection('properties')
      .doc(propertyId)
      .collection('taxa')
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => s.docs
            .map((d) => FirestoreMapping.taxonFromMap(d.id, d.data()))
            .toList(),
      );
  @override
  void saveTaxon(String propertyId, Taxon taxon) => _observe(
    taxon.id,
    firestore
        .collection('properties')
        .doc(propertyId)
        .collection('taxa')
        .doc(taxon.id)
        .set(FirestoreMapping.taxonToMap(taxon)),
  );
  @override
  void appendEvent(PlantEvent event) => _observe(
    event.id,
    _items(event.propertyId)
        .doc(event.itemId)
        .collection('events')
        .doc(event.id)
        .set(FirestoreMapping.eventToMap(event)),
  );
  @override
  Future<void> clearDeviceCache() async {
    await firestore.terminate();
    await firestore.clearPersistence();
  }
}
