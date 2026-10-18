import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/add_plant_screen.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/recording_map_platform.dart';

class PendingGps implements LocationRepository {
  final fix = Completer<LocationFix>();
  int calls = 0;
  @override
  Future<LocationFix> currentPosition() {
    calls++;
    return fix.future;
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  for (final copied in [true, false]) {
    testWidgets(
      'Add Plant picker confirms and cancels draft positions, copied=$copied',
      (tester) async {
        final previous = GoogleMapsFlutterPlatform.instance;
        final platform = RecordingMapPlatform();
        GoogleMapsFlutterPlatform.instance = platform;
        addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
        platform.initialize.complete();
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = LocalTrialRepository.open(prefs);
        final gps = PendingGps();
        final original = ManagedPlant(
          id: 'source',
          propertyId: repo.place.id,
          name: 'Source',
          taxonId: starterTaxonomy.taxa[2].id,
          location: Coordinates(51, 1),
          createdAt: DateTime(2026),
          plantedOn: '2020-04-10',
        );
        expect(original.templateWithHistory([]).location?.latitude, 51);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              orchardRepositoryProvider.overrideWithValue(repo),
              placeProvider.overrideWith((ref) async => repo.place),
              userProvider.overrideWith(
                (ref) => Stream.value(
                  const OrchardUser(LocalTrialRepository.userId),
                ),
              ),
              locationRepositoryProvider.overrideWithValue(gps),
              mapsConfiguredProvider.overrideWithValue(true),
              markerSymbolsProvider.overrideWith((ref) async => {}),
            ],
            child: MaterialApp(
              home: AddPlantScreen(template: copied ? original.template : null),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(gps.calls, copied ? 0 : 1);
        final button = find.text('Pick location on map');
        await tester.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        platform.attachPendingViews();
        await tester.pumpAndSettle();
        GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
        if (copied) {
          expect(map().initialCameraPosition.target, const LatLng(51, 1));
        }
        map().onTap!(const LatLng(52, 2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this location'));
        await tester.pumpAndSettle();
        // Choosing a map point must unblock saving even if GPS never responds.
        await tester.scrollUntilVisible(
          find.text('Save plant locally'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save plant locally'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.scrollUntilVisible(
          button,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        // A late GPS result must not overwrite the chosen draft point.
        gps.fix.complete(LocationFix(Coordinates(53, 3), 4));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        platform.attachPendingViews();
        await tester.pumpAndSettle();
        expect(map().initialCameraPosition.target, const LatLng(52, 2));
        map().onTap!(const LatLng(54, 4));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.plants, isEmpty);
        if (copied) {
          final save = find.text('Save plant locally');
          await tester.scrollUntilVisible(
            save,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(repo.plants.single.location.latitude, 52);
          expect(repo.plants.single.location.longitude, 2);
          expect(repo.plants.single.accuracyMeters, isNull);
          expect(repo.plants.single.plantedOn, '2020-04-10');
          await tester.tap(find.text('Add another'));
          await tester.pumpAndSettle();
          expect(gps.calls, 0);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(repo.plants.last.location.latitude, 52);
          expect(repo.plants.last.location.longitude, 2);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
