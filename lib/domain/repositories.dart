import 'dart:typed_data';

import 'models.dart';
import 'map_icons.dart';
import 'landscape.dart';
import 'work.dart';

class RepositorySnapshot<T> {
  const RepositorySnapshot(
    this.value, {
    required this.isFromCache,
    required this.hasPendingWrites,
  });
  final T value;
  final bool isFromCache;
  final bool hasPendingWrites;
}

class WriteFailure {
  const WriteFailure(this.recordId, this.message);
  final String recordId, message;
}

abstract interface class OrchardRepository {
  Future<Place> openDefaultPlace(String userId);
  Stream<RepositorySnapshot<List<ManagedPlant>>> watchPlants(String propertyId);
  Stream<RepositorySnapshot<List<PlantEvent>>> watchEvents(
    String propertyId,
    String itemId,
  );
  // Completes on local submission, never waits for server acknowledgement.
  void savePlant(ManagedPlant plant, {PlantEvent? plantingEvent});
  Stream<List<Taxon>> watchTaxa(String propertyId);
  void saveTaxon(String propertyId, Taxon taxon);
  Stream<List<MapIcon>> watchIcons(String propertyId);
  void saveIcon(String propertyId, MapIcon icon);
  void renameIcon(String propertyId, String iconId, String name);

  /// Remove image content, keeping a tombstone for existing/offline references.
  void deleteIcon(String propertyId, String iconId);
  void appendEvent(PlantEvent event);
  void updatePlant(ManagedPlant plant);
  Stream<RepositorySnapshot<List<OrchardTask>>> watchTasks(String propertyId);
  void saveTask(OrchardTask task);
  void saveTaskGroup(List<OrchardTask> tasks);
  Stream<RepositorySnapshot<List<OrchardSection>>> watchSections(
    String propertyId,
  );
  void saveSection(OrchardSection section);
  Stream<RepositorySnapshot<List<CropPlanting>>> watchCrops(String propertyId);
  void saveCrop(CropPlanting crop);
  Stream<RepositorySnapshot<List<CropHarvest>>> watchCropHarvests(
    String propertyId,
  );
  void appendCropHarvest(CropHarvest harvest);
  Stream<WriteFailure> get writeFailures;
  Stream<List<TaskPlan>> watchTaskPlans(String propertyId);
  void saveTaskPlan(TaskPlan plan);
  void saveTaskWithEvent(OrchardTask task, PlantEvent? event);
  void updateEvent(PlantEvent event);
  void deleteEvent(PlantEvent event);
  Future<void> deletePlant(String propertyId, String itemId);
  Future<void> deleteSection(String propertyId, String sectionId);
  void saveRowOrder(String propertyId, String sectionId, List<String> ids);
  Future<void> clearDeviceCache();
}

abstract interface class AuthRepository {
  Stream<OrchardUser?> get userChanges;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password);
  Future<void> signOut();
}

class LocationFix {
  const LocationFix(this.coordinates, this.accuracyMeters);
  final Coordinates coordinates;
  final double accuracyMeters;
}

abstract interface class LocationRepository {
  Future<LocationFix> currentPosition();
  Future<void> openSettings();
}

abstract interface class PhotoRepository {
  Future<void> upload(Photo photo, Uint8List bytes, String contentType);
}
