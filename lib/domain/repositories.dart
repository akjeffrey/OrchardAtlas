import 'dart:typed_data';

import 'models.dart';

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
  void savePlant(ManagedPlant plant);
  void appendEvent(PlantEvent event);
  Stream<WriteFailure> get writeFailures;
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
