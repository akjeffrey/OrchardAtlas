import 'dart:typed_data';

import 'models.dart';

/// Independently versioned orchard records, shared by local and remote adapters.
enum RecordKind { foraging, photo, activityRevision, reminder }

abstract interface class OrchardRecords {
  Stream<List<Map<String, dynamic>>> watchRecords(
    String orchard,
    RecordKind kind,
  );
  Future<void> putRecord(
    String orchard,
    RecordKind kind,
    String id,
    Map<String, dynamic> record,
  );
  Future<void> removeRecord(String orchard, RecordKind kind, String id);
}

class ResourceRecord {
  ResourceRecord({
    required this.id,
    required this.orchard,
    required String name,
    required this.taxonId,
    required this.location,
    required this.createdAt,
    this.startMonth = 1,
    this.endMonth = 12,
    this.public = false,
    this.notes = '',
  }) : name = requiredText(name, 'Resource name') {
    if (startMonth < 1 || startMonth > 12 || endMonth < 1 || endMonth > 12) {
      throw ArgumentError('Choose valid season months');
    }
    optionalText(notes, 10000);
  }
  final String id, orchard, name, taxonId, notes;
  final Coordinates location;
  final DateTime createdAt;
  final int startMonth, endMonth;
  final bool public;
  bool inSeason(int month) => startMonth <= endMonth
      ? month >= startMonth && month <= endMonth
      : month >= startMonth || month <= endMonth;
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'taxonId': taxonId,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'startMonth': startMonth,
    'endMonth': endMonth,
    'public': public,
    'notes': notes,
  };
  factory ResourceRecord.read(String orchard, Map<String, dynamic> d) =>
      ResourceRecord(
        id: d['id'] as String,
        orchard: orchard,
        name: d['name'] as String,
        taxonId: d['taxonId'] as String,
        location: Coordinates(
          (d['latitude'] as num).toDouble(),
          (d['longitude'] as num).toDouble(),
        ),
        createdAt: DateTime.parse(d['createdAt'] as String),
        startMonth: d['startMonth'] as int,
        endMonth: d['endMonth'] as int,
        public: d['public'] as bool,
        notes: d['notes'] as String? ?? '',
      );
}

class CapturedPhoto {
  const CapturedPhoto(this.image, this.thumbnail);
  final Uint8List image, thumbnail;
}

abstract interface class CameraRepository {
  Future<CapturedPhoto?> capture({required bool camera});
}

abstract interface class ReminderScheduler {
  Future<void> clear();
  Future<bool> requestPermission();
  Future<void> replace(
    String orchard,
    List<Map<String, dynamic>> notifications,
  );
}

class OrchardInvitation {
  const OrchardInvitation(
    this.id,
    this.orchard,
    this.orchardName,
    this.ownerId,
    this.email,
    this.role,
  );
  final String id, orchard, orchardName, ownerId, email;
  final PermissionRole role;
}

abstract interface class SharingRepository {
  Stream<List<ResourceRecord>> publicResources();
  Stream<List<OrchardInvitation>> invitations(String email);
  Stream<List<Permission>> members(String orchard);
  Future<void> invite(Place orchard, String email, PermissionRole role);
  Future<Place> accept(OrchardInvitation invitation, String userId);
  Future<void> revoke(String orchard, String userId);
}
