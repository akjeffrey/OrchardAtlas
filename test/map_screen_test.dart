import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/ui/map_screen.dart';

import 'support/recording_map_platform.dart';

class FixedLocation implements LocationRepository {
  @override
  Future<LocationFix> currentPosition() async =>
      LocationFix(Coordinates(52, 2), 5);
  @override
  Future<void> openSettings() async {}
}

void main() {
  late GoogleMapsFlutterPlatform previous;
  late RecordingMapPlatform platform;
  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    platform = RecordingMapPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = previous);
  Future<void> showMap(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          placeProvider.overrideWith(
            (ref) async => Place(
              id: 'place',
              name: 'Orchard',
              ownerId: 'alice',
              createdAt: DateTime.now(),
            ),
          ),
          plantsProvider.overrideWith(
            (ref) => Stream.value(
              const RepositorySnapshot<List<ManagedPlant>>(
                [],
                isFromCache: true,
                hasPendingWrites: false,
              ),
            ),
          ),
          locationRepositoryProvider.overrideWithValue(FixedLocation()),
        ],
        child: MaterialApp(home: MapScreen(focus: Coordinates(51, 1))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'GPS selection wins over a saved focus while native initialization is pending',
    (tester) async {
      await showMap(tester);
      await tester.tap(find.text('Current GPS location'));
      await tester.pumpAndSettle();
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, const LatLng(52, 2));
      platform.initialize.complete();
      await tester.pumpAndSettle();
      expect(
        platform.cameras.last,
        CameraUpdate.newLatLngZoom(const LatLng(52, 2), 19).toJson(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'native controller is disposed once by its owning GoogleMap widget',
    (tester) async {
      platform.initialize.complete();
      await showMap(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(platform.disposed, hasLength(1));
    },
  );
}
