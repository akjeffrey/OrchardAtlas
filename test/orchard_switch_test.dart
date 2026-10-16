import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/map_view_repository.dart';
import 'package:orchard_atlas/domain/filters.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/orchards.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/map_screen.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_filters.dart';

void main() {
  testWidgets(
    'orchard picker resets filters, scopes visible plants and restores that orchard view',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalTrialRepository.open(prefs);
      final north = await repo.createPlace(
        LocalTrialRepository.userId,
        'North orchard',
      );
      final commands = OrchardCommands(repo, starterTaxonomy);
      final taxon = starterTaxonomy.taxa.firstWhere(
        (t) => t.rank == TaxonRank.species,
      );
      for (final place in [repo.place, north]) {
        commands.addPlant(
          place: place,
          name: '${place.name} apple',
          taxonId: taxon.id,
          location: Coordinates(51, 1),
        );
      }
      final settings = DeviceMapViewRepository(prefs);
      await settings.save(
        LocalTrialRepository.userId,
        north.id,
        OrchardMapView(center: Coordinates(52, 2), zoom: 16),
      );
      final container = ProviderContainer(
        overrides: [
          orchardRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
          mapViewRepositoryProvider.overrideWithValue(settings),
          mapsConfiguredProvider.overrideWithValue(false),
          trialModeProvider.overrideWithValue(true),
        ],
      );
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const OrchardHome())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OrchardMap>(find.byType(OrchardMap))
            .plants
            .single
            .propertyId,
        repo.place.id,
      );
      container.read(plantFilterProvider.notifier).state = const PlantFilter(
        query: 'Trial',
      );
      await tester.tap(find.byTooltip('Orchard options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select orchard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('North orchard'));
      await tester.pumpAndSettle();
      expect(container.read(placeProvider).value!.id, north.id);
      expect(container.read(plantFilterProvider).query, '');
      final map = tester.widget<OrchardMap>(find.byType(OrchardMap));
      expect(map.plants.single.propertyId, north.id);
      expect(map.center!.latitude, 52);
      expect(map.initialCamera!.zoom, 16);
      await tester.runAsync(() async {
        expect(
          (await LocalTrialRepository.open(prefs)
                  .openDefaultPlace(LocalTrialRepository.userId))
              .id,
          north.id,
        );
      });
      await tester.tap(find.byTooltip('Orchard options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select orchard'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New orchard name'),
        'West orchard',
      );
      await tester.tap(find.text('Create orchard'));
      await tester.pumpAndSettle();
      expect(container.read(placeProvider).value!.name, 'West orchard');
      expect(
        tester.widget<OrchardMap>(find.byType(OrchardMap)).plants,
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
