import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/orchards.dart';
import '../domain/landscape.dart';
import 'landscape_mapping.dart';
import '../domain/repositories.dart';
import 'firestore_mapping.dart';

class FirestoreOrchardRepository
    implements OrchardRepository, OrchardDirectoryRepository {
  FirestoreOrchardRepository(this.firestore, this.preferences);
  final FirebaseFirestore firestore;
  final SharedPreferences preferences;
  final _pendingPlaces = <String, Place>{};
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
      final pending = _pendingPlaces[knownId];
      if (pending != null && pending.ownerId == userId) return pending;
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
  Stream<List<Place>> watchPlaces(String userId) => firestore
      .collection('properties')
      .where('ownerId', isEqualTo: userId)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        final places = <String, Place>{
          for (final p in _pendingPlaces.values.where(
            (p) => p.ownerId == userId,
          ))
            p.id: p,
          for (final d in snapshot.docs)
            d.id: FirestoreMapping.placeFromMap(d.id, d.data()),
        }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
        return places;
      });
  @override
  Future<Place> createPlace(String userId, String name) async {
    final place = Place(
      id: const Uuid().v4(),
      name: requiredText(name, 'Orchard name'),
      ownerId: userId,
      createdAt: DateTime.now().toUtc(),
    );
    _pendingPlaces[place.id] = place;
    _observe(
      place.id,
      firestore
          .collection('properties')
          .doc(place.id)
          .set(FirestoreMapping.placeToMap(place))
          .whenComplete(() => _pendingPlaces.remove(place.id)),
    );
    return place;
  }

  @override
  Future<void> selectPlace(String userId, String placeId) async {
    final pending = _pendingPlaces[placeId];
    final place =
        pending ??
        await () async {
          final doc = await _cachedProperty(
            firestore.collection('properties').doc(placeId),
          );
          if (!doc.exists) throw StateError('Orchard unavailable');
          return FirestoreMapping.placeFromMap(doc.id, doc.data()!);
        }();
    if (place.ownerId != userId) {
      throw StateError('Orchard belongs to another account');
    }
    if (!await preferences.setString('default-place:$userId', place.id)) {
      throw StateError('Could not save orchard selection');
    }
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
  void updatePlant(ManagedPlant plant) => _observe(
    plant.id,
    _items(plant.propertyId)
        .doc(plant.id)
        .update(FirestoreMapping.editablePlantToMap(plant)),
  );
  @override
  Stream<RepositorySnapshot<List<OrchardTask>>> watchTasks(String propertyId) =>
      firestore
          .collection('properties')
          .doc(propertyId)
          .collection('tasks')
          .snapshots(includeMetadataChanges: true)
          .map(
            (s) => RepositorySnapshot(
              s.docs
                  .map(
                    (d) => FirestoreMapping.taskFromMap(
                      propertyId,
                      d.id,
                      d.data(),
                    ),
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'),
                ),
              isFromCache: s.metadata.isFromCache,
              hasPendingWrites: s.metadata.hasPendingWrites,
            ),
          );
  @override
  void saveTask(OrchardTask task) => _observe(
    task.id,
    firestore
        .collection('properties')
        .doc(task.propertyId)
        .collection('tasks')
        .doc(task.id)
        .set(FirestoreMapping.taskToMap(task)),
  );

  @override
  void saveTaskGroup(List<OrchardTask> tasks) {
    if (tasks.isEmpty ||
        tasks.length > 400 ||
        tasks.first.groupId == null ||
        tasks.any(
          (t) =>
              t.propertyId != tasks.first.propertyId ||
              t.groupId != tasks.first.groupId,
        ) ||
        tasks.map((t) => t.itemId ?? t.sectionId ?? t.cropId).toSet().length !=
            tasks.length ||
        tasks.map((t) => t.id).toSet().length != tasks.length) {
      throw ArgumentError('Invalid task group');
    }
    final batch = firestore.batch();
    for (final task in tasks) {
      batch.set(
        firestore
            .collection('properties')
            .doc(task.propertyId)
            .collection('tasks')
            .doc(task.id),
        FirestoreMapping.taskToMap(task),
      );
    }
    _observe(tasks.first.groupId!, batch.commit());
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String propertyId,
    String name,
  ) => firestore.collection('properties').doc(propertyId).collection(name);
  Stream<RepositorySnapshot<List<T>>> _landscapeStream<T>(
    String propertyId,
    String name,
    T Function(String, Map<String, dynamic>) decode,
  ) => _collection(propertyId, name)
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => RepositorySnapshot(
          s.docs.map((d) => decode(d.id, d.data())).toList(),
          isFromCache: s.metadata.isFromCache,
          hasPendingWrites: s.metadata.hasPendingWrites,
        ),
      );
  @override
  Stream<RepositorySnapshot<List<OrchardSection>>> watchSections(
    String propertyId,
  ) => _landscapeStream(
    propertyId,
    'sections',
    (id, d) => LandscapeMapping.readSection(propertyId, id, d),
  );
  @override
  void saveSection(OrchardSection section) => _observe(
    section.id,
    _collection(
      section.propertyId,
      'sections',
    ).doc(section.id).set(LandscapeMapping.section(section, native: true)),
  );
  @override
  Stream<RepositorySnapshot<List<CropPlanting>>> watchCrops(
    String propertyId,
  ) => _landscapeStream(
    propertyId,
    'crops',
    (id, d) => LandscapeMapping.readCrop(propertyId, id, d),
  );
  @override
  void saveCrop(CropPlanting crop) => _observe(
    crop.id,
    _collection(
      crop.propertyId,
      'crops',
    ).doc(crop.id).set(LandscapeMapping.crop(crop, native: true)),
  );
  @override
  Stream<RepositorySnapshot<List<CropHarvest>>> watchCropHarvests(
    String propertyId,
  ) => _landscapeStream(
    propertyId,
    'cropHarvests',
    (id, d) => LandscapeMapping.readHarvest(propertyId, id, d),
  );
  @override
  void appendCropHarvest(CropHarvest harvest) => _observe(
    harvest.id,
    _collection(
      harvest.propertyId,
      'cropHarvests',
    ).doc(harvest.id).set(LandscapeMapping.harvest(harvest, native: true)),
  );

  @override
  Future<void> clearDeviceCache() async {
    await firestore.terminate();
    await firestore.clearPersistence();
  }
}
