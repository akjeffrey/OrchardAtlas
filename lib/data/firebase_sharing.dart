import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../domain/extensions.dart';
import '../domain/models.dart';
import 'firestore_mapping.dart';

class FirebaseSharing implements SharingRepository {
  FirebaseSharing(this.db);
  final FirebaseFirestore db;
  @override
  Stream<List<ResourceRecord>> publicResources() => db
      .collection('publicResources')
      .limit(200)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            ResourceRecord.read(d['orchard'] as String, {
              ...d.data(),
              'public': true,
              'notes': '',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            }),
        ],
      );
  @override
  Stream<List<OrchardInvitation>> invitations(String email) => db
      .collection('invitations')
      .where('email', isEqualTo: email.toLowerCase())
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            OrchardInvitation(
              d.id,
              d['orchard'] as String,
              d['orchardName'] as String,
              d['ownerId'] as String,
              d['email'] as String,
              PermissionRole.values.byName(d['role'] as String),
            ),
        ],
      );
  @override
  Stream<List<Permission>> members(String orchard) => db
      .collection('properties')
      .doc(orchard)
      .collection('members')
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            Permission(
              orchard,
              d.id,
              PermissionRole.values.byName(d['role'] as String),
            ),
        ],
      );
  @override
  Future<void> invite(Place orchard, String email, PermissionRole role) async {
    email = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.length > 254 ||
        role == PermissionRole.owner) {
      throw ArgumentError('Enter a valid email and editor/viewer role');
    }
    await db.collection('invitations').doc(const Uuid().v4()).set({
      'orchard': orchard.id,
      'orchardName': orchard.name,
      'ownerId': orchard.ownerId,
      'email': email,
      'role': role.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Place> accept(OrchardInvitation invitation, String userId) async {
    final batch = db.batch();
    batch.set(
      db
          .collection('properties')
          .doc(invitation.orchard)
          .collection('members')
          .doc(userId),
      {'role': invitation.role.name, 'invitationId': invitation.id},
    );
    batch.set(
      db
          .collection('users')
          .doc(userId)
          .collection('orchards')
          .doc(invitation.orchard),
      {'invitationId': invitation.id},
    );
    batch.delete(db.collection('invitations').doc(invitation.id));
    await batch.commit();
    final d = await db.collection('properties').doc(invitation.orchard).get();
    return FirestoreMapping.placeFromMap(d.id, d.data()!);
  }

  @override
  Future<void> revoke(String orchard, String userId) => db
      .collection('properties')
      .doc(orchard)
      .collection('members')
      .doc(userId)
      .delete();
}
