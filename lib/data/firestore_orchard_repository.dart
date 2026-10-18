import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/work.dart';
import 'work_mapping.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/map_icons.dart';
import 'icon_mapping.dart';
import '../domain/orchards.dart';
import '../domain/landscape.dart';
import 'landscape_mapping.dart';
import '../domain/repositories.dart';
import 'firestore_mapping.dart';

class FirestoreOrchardRepository
    implements OrchardRepository, OrchardDirectoryRepository {
  FirestoreOrchardRepository(this.firestore, this.preferences, {this.storage});
  final FirebaseStorage? storage;
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
        name: 'Home Orchard',
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
  Future<Place> renamePlace(String userId, String placeId, String name) async {
    final doc = await _cachedProperty(
      firestore.collection('properties').doc(placeId),
    );
    final old = FirestoreMapping.placeFromMap(doc.id, doc.data()!);
    if (old.ownerId != userId) {
      throw StateError('Orchard belongs to another user');
    }
    final renamed = Place(
      id: old.id,
      name: name,
      ownerId: old.ownerId,
      createdAt: old.createdAt,
    );
    _observe(placeId, doc.reference.update({'name': renamed.name}));
    return renamed;
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
  Stream<List<MapIcon>> watchIcons(String propertyId) => firestore
      .collection('properties')
      .doc(propertyId)
      .collection('icons')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map((d) => IconMapping.read(d.id, d.data())).toList());
  @override
  void saveIcon(String propertyId, MapIcon icon) => _observe(
    icon.id,
    firestore
        .collection('properties')
        .doc(propertyId)
        .collection('icons')
        .doc(icon.id)
        .set(IconMapping.write(icon)),
  );

  @override
  void deleteIcon(String propertyId, String iconId) => _observe(
    iconId,
    firestore
        .collection('properties')
        .doc(propertyId)
        .collection('icons')
        .doc(iconId)
        .update(IconMapping.write(MapIcon.deleted(id: iconId))),
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
  void updatePlant(ManagedPlant plant) =>
      _observe(plant.id, _updatePlant(plant));
  Future<void> _updatePlant(ManagedPlant plant) async {
    final item = _items(plant.propertyId).doc(plant.id);
    final old = await item.get();
    final batch = firestore.batch();
    batch.update(item, FirestoreMapping.editablePlantToMap(plant));
    if (old.data()?['plantedOn'] != plant.plantedOn) {
      final history = await item
          .collection('events')
          .where('type', isEqualTo: 'planting')
          .get();
      final events = history.docs
          .where((e) => e.data()['taskId'] == null)
          .toList();
      for (final e in events) {
        batch.delete(e.reference);
      }
      if (plant.plantedOn != null) {
        final owner = await _cachedProperty(
          firestore.collection('properties').doc(plant.propertyId),
        );
        final id = events.firstOrNull?.id ?? const Uuid().v4();
        final event = PlantEvent(
          id: id,
          propertyId: plant.propertyId,
          itemId: plant.id,
          authorId: owner.data()!['ownerId'] as String,
          type: ActivityType.planting,
          occurredAt: parseCalendarDate(plant.plantedOn!).toUtc(),
          activityDate: plant.plantedOn!,
          recordedAt: events.isEmpty
              ? DateTime.now().toUtc()
              : (events.first.data()['recordedAt'] as Timestamp).toDate(),
        );
        batch.set(
          item.collection('events').doc(id),
          FirestoreMapping.eventToMap(event),
        );
      }
    }
    await batch.commit();
  }

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
  Stream<List<TaskPlan>> watchTaskPlans(String propertyId) =>
      _collection(propertyId, 'taskPlans')
          .snapshots(includeMetadataChanges: true)
          .map(
            (s) => [
              for (final d in s.docs)
                WorkMapping.readPlan(propertyId, d.id, d.data()),
            ],
          );
  @override
  void saveTaskPlan(TaskPlan plan) => _observe(
    plan.id,
    _collection(
      plan.propertyId,
      'taskPlans',
    ).doc(plan.id).set(WorkMapping.plan(plan, native: true)),
  );
  @override
  void saveTaskWithEvent(OrchardTask task, PlantEvent? event) {
    if (event != null &&
        (event.taskId != task.id ||
            event.itemId != task.itemId ||
            event.propertyId != task.propertyId)) {
      throw ArgumentError('Invalid completion event');
    }
    final batch = firestore.batch();
    batch.set(
      _collection(task.propertyId, 'tasks').doc(task.id),
      FirestoreMapping.taskToMap(task),
    );
    if (task.itemId != null) {
      final reference = _items(task.propertyId)
          .doc(task.itemId)
          .collection('events')
          .doc(linkedEventId(task.id));
      if (event == null) {
        batch.delete(reference);
      } else {
        batch.set(reference, FirestoreMapping.eventToMap(event));
      }
    }
    _observe(task.id, batch.commit());
  }

  @override
  void updateEvent(PlantEvent event) => _observe(
    event.id,
    _items(event.propertyId)
        .doc(event.itemId)
        .collection('events')
        .doc(event.id)
        .update(FirestoreMapping.eventToMap(event)),
  );
  @override
  void deleteEvent(PlantEvent event) {
    final batch = firestore.batch();
    batch.delete(
      _items(event.propertyId)
          .doc(event.itemId)
          .collection('events')
          .doc(event.id),
    );
    if (event.taskId != null) {
      batch.update(_collection(event.propertyId, 'tasks').doc(event.taskId), {
        'status': 'open',
        'completedOn': null,
      });
    }
    _observe(event.id, batch.commit());
  }

  @override
  void saveRowOrder(String propertyId, String sectionId, List<String> ids) {
    if (ids.length > 400 || ids.toSet().length != ids.length) {
      throw ArgumentError('Reorder at most 400 plants at once');
    }
    final batch = firestore.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(_items(propertyId).doc(ids[i]), {'rowOrder': i.toDouble()});
    }
    _observe(sectionId, batch.commit());
  }

  Future<void> _removePlantFiles(
    String propertyId,
    DocumentSnapshot<Map<String, dynamic>> plant,
  ) async {
    final reference = plant.reference;
    for (final child in ['events', 'photos']) {
      final records = await reference
          .collection(child)
          .get(const GetOptions(source: Source.server));
      for (final doc in records.docs) {
        final path = doc.data()['storagePath'];
        if (path is String) {
          if (!path.startsWith('properties/$propertyId/')) {
            throw StateError('Photo path does not belong to orchard');
          }
          if (storage == null) {
            throw StateError('Photo storage is not configured');
          }
          try {
            await storage!.ref(path).delete();
          } on FirebaseException catch (e) {
            if (e.code != 'object-not-found') rethrow;
          }
        }
        await doc.reference.delete();
      }
    }
    await reference.delete();
  }

  Future<void> _deleteTargets(
    String propertyId,
    Set<String> sectionIds,
    Set<String> plantIds,
    Set<String> cropIds,
  ) async {
    final deletedPlans = <String>{};
    final deletedTasks = <String>{};
    for (final collection in ['taskPlans', 'tasks', 'cropHarvests']) {
      final records = await _collection(
        propertyId,
        collection,
      ).get(const GetOptions(source: Source.server));
      for (final d in records.docs) {
        final v = d.data();
        if (deletedPlans.contains(v['planId']) ||
            plantIds.contains(v['itemId']) ||
            sectionIds.contains(v['sectionId']) ||
            cropIds.contains(v['cropId'])) {
          if (collection == 'taskPlans') deletedPlans.add(d.id);
          if (collection == 'tasks') {
            deletedTasks.add(d.id);
            if (v['itemId'] is String && !plantIds.contains(v['itemId'])) {
              final linked = await _items(propertyId)
                  .doc(v['itemId'] as String)
                  .collection('events')
                  .where('taskId', isEqualTo: d.id)
                  .get(const GetOptions(source: Source.server));
              for (final event in linked.docs) {
                await event.reference.delete();
              }
            }
          }
          await d.reference.delete();
        }
      }
    }
    for (final id in plantIds) {
      final plant = await _items(propertyId)
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (plant.exists) await _removePlantFiles(propertyId, plant);
    }
    for (final id in cropIds) {
      await _collection(propertyId, 'crops').doc(id).delete();
    }
    for (final id in sectionIds.toList().reversed) {
      await _collection(propertyId, 'sections').doc(id).delete();
    }
    final remaining = await _collection(
      propertyId,
      'tasks',
    ).get(const GetOptions(source: Source.server));
    for (final d in remaining.docs) {
      final v = d.data();
      if (deletedPlans.contains(v['planId']) ||
          deletedTasks.contains(d.id) ||
          plantIds.contains(v['itemId']) ||
          sectionIds.contains(v['sectionId']) ||
          cropIds.contains(v['cropId'])) {
        await d.reference.delete();
      }
    }
  }

  @override
  Future<void> deletePlant(String propertyId, String id) =>
      _deleteTargets(propertyId, {}, {id}, {});
  @override
  Future<void> deleteSection(String propertyId, String id) async {
    final records = await _collection(
      propertyId,
      'sections',
    ).get(const GetOptions(source: Source.server));
    final sections = [
      for (final d in records.docs)
        LandscapeMapping.readSection(propertyId, d.id, d.data()),
    ];
    final ids = sectionDescendants(id, sections);
    final plants = await _items(propertyId)
        .get(const GetOptions(source: Source.server));
    final crops = await _collection(
      propertyId,
      'crops',
    ).get(const GetOptions(source: Source.server));
    await _deleteTargets(
      propertyId,
      ids,
      plants.docs
          .where((p) => ids.contains(p.data()['sectionId']))
          .map((p) => p.id)
          .toSet(),
      crops.docs
          .where((c) => ids.contains(c.data()['sectionId']))
          .map((c) => c.id)
          .toSet(),
    );
  }

  @override
  Future<void> clearDeviceCache() async {
    await firestore.terminate();
    await firestore.clearPersistence();
  }
}
