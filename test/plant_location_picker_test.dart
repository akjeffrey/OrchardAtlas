import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/edit_plant_screen.dart';
import 'package:orchard_atlas/ui/plant_location_picker.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/recording_map_platform.dart';

void main() {
  for (final outcome in ['save', 'cancel', 'back', 'invalid input']) {
    testWidgets('map location editor: $outcome', (tester) async {
      final oldPlatform = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = oldPlatform);
      platform.initialize.complete();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repo = LocalTrialRepository.open(preferences);
      repo.saveSection(
        OrchardSection(
          id: 'row',
          propertyId: repo.place.id,
          name: 'Apple row',
          kind: SectionKind.row,
          vertices: [Coordinates(51, 1), Coordinates(51, 1.01)],
          createdAt: DateTime(2026),
        ),
      );
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Apple',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
        accuracyMeters: 5,
        plantingDate: DateTime(2022, 4, 10),
        authorId: LocalTrialRepository.userId,
        sectionId: 'row',
      );
      final events = repo.events.map((e) => e.id).toList();
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(path: '/edit', builder: (_, _) => EditPlantScreen(plant.id)),
          GoRoute(
            path: '/plants/:id',
            builder: (_, _) => const Scaffold(body: Text('Changes saved')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
            mapsConfiguredProvider.overrideWithValue(true),
            markerSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Plant name'),
        'Draft name',
      );
      final draftName = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Plant name'))
          .controller!;
      if (outcome == 'invalid input') {
        await tester.enterText(
          find.widgetWithText(TextField, 'Latitude'),
          'oops',
        );
      }
      await tester.ensureVisible(find.text('Pick location on map'));
      await tester.tap(find.text('Pick location on map'));
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map().mapType, MapType.satellite);
      expect(map().initialCameraPosition.target, const LatLng(51, 1));
      map().onTap!(const LatLng(51.01, 1.01));
      await tester.pump();
      expect(map().markers.single.position, const LatLng(51.01, 1.01));
      expect(map().markers.single.draggable, isTrue);
      map().markers.single.onDragEnd!(const LatLng(51.02, 1.02));
      await tester.pump();
      expect(map().markers.single.position, const LatLng(51.02, 1.02));
      expect(repo.plants.single.location.latitude, 51);
      if (outcome == 'back') {
        Navigator.of(tester.element(find.byType(PlantLocationPicker))).pop();
      } else {
        await tester.tap(
          find.text(outcome == 'cancel' ? 'Cancel' : 'Use this location'),
        );
      }
      await tester.pumpAndSettle();
      final confirmed = outcome == 'save' || outcome == 'invalid input';
      String field(String label) => tester
          .widget<TextField>(find.widgetWithText(TextField, label))
          .controller!
          .text;
      expect(field('Latitude'), confirmed ? '51.02' : '51.0');
      expect(field('Longitude'), confirmed ? '1.02' : '1.0');
      expect(draftName.text, 'Draft name');
      expect(repo.plants.single.location.latitude, 51);
      // Reopening starts at the editor's draft, not the old saved point.
      await tester.ensureVisible(find.text('Pick location on map'));
      await tester.tap(find.text('Pick location on map'));
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      expect(
        map().initialCameraPosition.target,
        confirmed ? const LatLng(51.02, 1.02) : const LatLng(51, 1),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Changes saved'), findsOneWidget);
      final saved = LocalTrialRepository.open(preferences).plants.single;
      expect(saved.name, 'Draft name');
      expect(saved.location.latitude, confirmed ? 51.02 : 51);
      expect(saved.location.longitude, confirmed ? 1.02 : 1);
      expect(saved.accuracyMeters, confirmed ? isNull : 5);
      expect(saved.id, plant.id);
      expect(saved.sectionId, plant.sectionId);
      expect(saved.rowOrder, plant.rowOrder);
      expect(saved.taxonId, plant.taxonId);
      expect(saved.plantedOn, plant.plantedOn);
      expect(repo.events.map((e) => e.id), events);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
