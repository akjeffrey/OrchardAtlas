import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/add_plant_screen.dart';
import 'package:orchard_atlas/ui/archived_plants.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/recording_map_platform.dart';

class _Gps implements LocationRepository {
  int calls = 0;
  @override
  Future<LocationFix> currentPosition() async {
    calls++;
    return LocationFix(Coordinates(20, 20), 5);
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  testWidgets(
    'grouped and archived markers stay hidden while section geometry and icons remain',
    (tester) async {
      final old = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = old);
      platform.initialize.complete();
      final repo = await repository();
      final row = OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Blueberries',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.1)],
        createdAt: DateTime(2026),
        color: 0xff123456,
        symbol: PlantSymbol.berry,
      );
      ManagedPlant plant(
        String id, {
        String? section,
        ItemStatus status = ItemStatus.active,
      }) => ManagedPlant(
        id: id,
        propertyId: repo.place.id,
        name: id,
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
        sectionId: section,
        status: status,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapsConfiguredProvider.overrideWithValue(true),
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
            markerSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrchardMap(
                sections: [row],
                plants: [
                  plant('visible'),
                  plant('grouped', section: 'row'),
                  plant('archived', status: ItemStatus.archived),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.polylines.single.color, const Color(0xff123456));
      final ids = map.markers.map((m) => m.markerId.value).toList();
      expect(ids, contains('visible'));
      expect(ids, isNot(contains('grouped')));
      expect(ids, isNot(contains('archived')));
      expect(
        map.markers.any((m) => m.infoWindow.title == 'Blueberries'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'archive is a list and unarchive restores a plant without a map',
    (tester) async {
      final repo = await repository();
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Archived apple',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
      );
      repo.updatePlant(plant.copyWith(status: ItemStatus.archived));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
          ],
          child: const MaterialApp(home: ArchivedPlantsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archived apple'), findsOneWidget);
      expect(find.byType(GoogleMap), findsNothing);
      await tester.tap(find.byTooltip('Unarchive plant'));
      await tester.pumpAndSettle();
      expect(repo.plants.single.status, ItemStatus.active);
      expect(find.text('Archived apple'), findsNothing);
    },
  );
  testWidgets(
    'similar legacy cultivar uses three selectors and the row location instead of GPS',
    (tester) async {
      final repo = await repository();
      final gps = _Gps();
      repo.saveSection(
        OrchardSection(
          id: 'row',
          propertyId: repo.place.id,
          name: 'Row',
          kind: SectionKind.row,
          vertices: [Coordinates(51, 1), Coordinates(51, 1.1)],
          createdAt: DateTime(2026),
        ),
      );
      final cultivar = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Honeycrisp',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
            locationRepositoryProvider.overrideWithValue(gps),
          ],
          child: MaterialApp(
            home: AddPlantScreen(
              template: PlantTemplate(
                name: 'Honeycrisp',
                taxonId: cultivar.id,
                sectionId: 'row',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gps.calls, 0);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Variety'), findsOneWidget);
      expect(find.text('Cultivar'), findsNothing);
      expect(find.textContaining('Honeycrisp'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Using Row location'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Using Row location'), findsOneWidget);
    },
  );
}
