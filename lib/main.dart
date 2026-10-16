import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/providers.dart';
import 'data/firestore_orchard_repository.dart';
import 'data/local_trial_repository.dart';
import 'data/platform_repositories.dart';
import 'data/map_services.dart';
import 'data/map_view_repository.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final mapsConfigured = await DeviceAddressSearchRepository.mapsConfigured();
    if (const bool.fromEnvironment('TRIAL_MODE')) {
      final preferences = await SharedPreferences.getInstance();
      runApp(
        ProviderScope(
          overrides: [
            mapViewRepositoryProvider.overrideWithValue(
              DeviceMapViewRepository(preferences),
            ),
            mapsConfiguredProvider.overrideWithValue(mapsConfigured),
            addressSearchRepositoryProvider.overrideWithValue(
              DeviceAddressSearchRepository(),
            ),
            trialModeProvider.overrideWithValue(true),
            orchardRepositoryProvider.overrideWithValue(
              LocalTrialRepository.open(preferences),
            ),
            authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
            locationRepositoryProvider.overrideWithValue(
              DeviceLocationRepository(),
            ),
          ],
          child: const OrchardAtlasApp(),
        ),
      );
      return;
    }
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    if ([project, apiKey, appId, sender].any((s) => s.isEmpty)) {
      throw StateError(
        'Supply Firebase dart defines. See docs/developer-setup.md.',
      );
    }
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: sender,
        projectId: project,
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: 'com.orchardatlas.orchardAtlas',
      ),
    );
    final firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: true);
    const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    if (emulatorHost.isNotEmpty) {
      firestore.useFirestoreEmulator(emulatorHost, 8080);
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
    }
    final preferences = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [
          mapViewRepositoryProvider.overrideWithValue(
            DeviceMapViewRepository(preferences),
          ),
          mapsConfiguredProvider.overrideWithValue(mapsConfigured),
          addressSearchRepositoryProvider.overrideWithValue(
            DeviceAddressSearchRepository(),
          ),
          orchardRepositoryProvider.overrideWithValue(
            FirestoreOrchardRepository(firestore, preferences),
          ),
          authRepositoryProvider.overrideWithValue(
            FirebaseAuthRepository(FirebaseAuth.instance),
          ),
          locationRepositoryProvider.overrideWithValue(
            DeviceLocationRepository(),
          ),
          photoRepositoryProvider.overrideWithValue(
            FirebasePhotoRepository(FirebaseStorage.instance),
          ),
        ],
        child: const OrchardAtlasApp(),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'OrchardAtlas could not initialize. Check Firebase configuration and native setup in docs/developer-setup.md, then restart.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
