import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this.auth);
  final FirebaseAuth auth;
  @override
  Stream<OrchardUser?> get userChanges => auth.authStateChanges().map(
    (u) => u == null ? null : OrchardUser(u.uid, displayName: u.displayName),
  );
  @override
  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> register(String email, String password) async {
    await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() => auth.signOut();
}

class DeviceLocationRepository implements LocationRepository {
  @override
  Future<LocationFix> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Location services are off. Enable them or enter coordinates manually.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is blocked. Open app settings or enter coordinates manually.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission denied. You can enter coordinates manually.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return LocationFix(
      Coordinates(position.latitude, position.longitude),
      position.accuracy,
    );
  }

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}

class FirebasePhotoRepository implements PhotoRepository {
  FirebasePhotoRepository(this.storage);
  final FirebaseStorage storage;
  @override
  Future<void> upload(Photo photo, Uint8List bytes, String contentType) async {
    // The production V1 rules deny uploads. This port is for the next photo slice.
    await storage
        .ref(photo.storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));
  }
}
