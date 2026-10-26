import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/crops_screen.dart';
import 'package:orchard_atlas/ui/edit_plant_screen.dart';
import 'package:orchard_atlas/ui/icon_picker.dart';
import 'package:orchard_atlas/ui/life_cycle_button.dart';
import 'package:orchard_atlas/ui/map_screen.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';
import 'package:orchard_atlas/ui/plants_list.dart';
import 'package:orchard_atlas/ui/tasks_screen.dart';
import 'package:orchard_atlas/ui/version_history_screen.dart';
import 'package:orchard_atlas/ui/app_version_banner.dart';

import 'support/recording_map_platform.dart';
import 'support/icon_fixture.dart';

void workflowTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, body, timeout: const Timeout(Duration(seconds: 30)));

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalTrialRepository.open(
      await SharedPreferences.getInstance(),
    );
    repo.saveSection(
      OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Row',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.001)],
        createdAt: DateTime(2026),
      ),
    );
    return repo;
  }

  Widget wrap(LocalTrialRepository repo, Widget child) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      placeProvider.overrideWith((ref) async => repo.place),
    ],
    child: child,
  );
  Finder field(String name) => find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == name,
  );
  Future<void> choose(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.tap(field(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  workflowTest(
    'seasonal planting uses cascading selectors and can create a custom variety without losing its season or notes',
    (tester) async {
      final repo = await repository();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) => CropFormScreen(section: repo.sections.single),
          ),
          GoRoute(
            path: '/crops/:id',
            builder: (_, _) => const Scaffold(body: Text('Season saved')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(repo, MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'Group', 'Fruit trees');
      await choose(tester, 'Type', 'Apple (Malus)');
      await choose(tester, 'Variety', '+ Add new option…');
      await tester.enterText(
        find.widgetWithText(TextField, 'Option name'),
        'Orchard variety',
      );
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      expect(repo.taxa.single.name, 'Orchard variety');
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Season / year'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Season / year'),
        '2027 autumn',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Planting notes'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Planting notes'),
        'Keep this note',
      );
      await tester.scrollUntilVisible(
        find.text('Save planting'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save planting'));
      await tester.pumpAndSettle();
      expect(find.text('Season saved'), findsOneWidget);
      expect(repo.crops.single.taxonId, repo.taxa.single.id);
      expect(repo.crops.single.label, 'Orchard variety');
      expect(repo.crops.single.season, '2027 autumn');
      expect(repo.crops.single.notes, 'Keep this note');
      expect(repo.crops.single.lifeCycle, PlantLifeCycle.annual);
    },
  );
  for (final depth in [1, 2, 3]) {
    workflowTest(
      'task target permits depth $depth without requiring further classification',
      (tester) async {
        final repo = await repository();
        final gala = starterTaxonomy.taxa.firstWhere((t) => t.name == 'Gala');
        final pear = starterTaxonomy.taxa.firstWhere(
          (t) => t.name == 'European pear',
        );
        for (final t in [gala, pear]) {
          OrchardCommands(repo, starterTaxonomy).addPlant(
            place: repo.place,
            name: t.name,
            taxonId: t.id,
            location: Coordinates(51, 1),
          );
        }
        final router = GoRouter(
          initialLocation: '/new',
          routes: [
            GoRoute(path: '/new', builder: (_, _) => const TaskFormScreen()),
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Task saved')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          wrap(repo, MaterialApp.router(routerConfig: router)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Whole orchard'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Task title'),
          'Care',
        );
        await choose(tester, 'Group', 'Fruit trees');
        if (depth >= 2) await choose(tester, 'Type', 'Apple (Malus)');
        if (depth >= 3) await choose(tester, 'Variety', 'Gala');
        await tester.scrollUntilVisible(
          find.text('Create group checklist'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Create group checklist'));
        await tester.pumpAndSettle();
        expect(find.text('Task saved'), findsOneWidget);
        expect(repo.tasks.length, depth == 1 ? 2 : 1);
        final plans = await tester.runAsync(
          () => repo.watchTaskPlans(repo.place.id).first,
        );
        final plan = plans!.single;
        expect(
          plan.taxonId,
          starterTaxonomy.taxa
              .firstWhere(
                (t) =>
                    t.name ==
                    ['Fruit trees', 'Apple (Malus)', 'Gala'][depth - 1],
              )
              .id,
        );
      },
    );
  }
  workflowTest(
    'management conversion confirms season, can cancel and converts both record types back',
    (tester) async {
      final repo = await repository();
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Plant',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
      );
      Widget view(ManagedPlant value) => wrap(
        repo,
        MaterialApp(
          home: Scaffold(body: LifeCycleButton(plant: value)),
        ),
      );
      await tester.pumpWidget(view(plant));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert to annual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.plants.single.lifeCycle, PlantLifeCycle.perennial);
      await tester.tap(find.text('Convert to annual'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a season / year'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '2027');
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      expect(repo.plants.single.lifeCycle, PlantLifeCycle.annual);
      expect(repo.plants.single.season, '2027');
      await tester.pumpWidget(view(repo.plants.single));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert to perennial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      expect(repo.plants.single.lifeCycle, PlantLifeCycle.perennial);
      expect(repo.plants.single.id, plant.id);
      final crop = CropPlanting(
        id: 'crop',
        propertyId: repo.place.id,
        sectionId: 'row',
        taxonId: plant.taxonId,
        label: 'Crop',
        season: '2026',
        createdAt: DateTime(2026),
      );
      repo.saveCrop(crop);
      await tester.pumpWidget(
        wrap(
          repo,
          MaterialApp(
            home: Scaffold(body: LifeCycleButton(crop: crop)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert to perennial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();
      expect(repo.crops.single.lifeCycle, PlantLifeCycle.perennial);
    },
  );
  workflowTest(
    'plant list resolves inherited custom map icons for plants and seasonal records, including deletion fallback',
    (tester) async {
      final repo = await repository();
      final type = starterTaxonomy.taxa[1], variety = starterTaxonomy.taxa[2];
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'art', name: 'Art', png: iconPng()),
      );
      repo.saveTaxon(
        repo.place.id,
        Taxon(
          id: type.id,
          name: type.name,
          rank: type.rank,
          parentId: type.parentId,
          customIconId: 'art',
          iconOverride: true,
        ),
      );
      OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Plant',
        taxonId: variety.id,
        location: Coordinates(51, 1),
      );
      repo.saveCrop(
        CropPlanting(
          id: 'crop',
          propertyId: repo.place.id,
          sectionId: 'row',
          taxonId: variety.id,
          label: 'Crop',
          season: '2026',
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        wrap(repo, const MaterialApp(home: Scaffold(body: PlantsList()))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plant'), findsOneWidget);
      expect(find.text('Crop'), findsOneWidget);
      final icons = tester.widgetList<IconPreview>(find.byType(IconPreview));
      expect(icons, hasLength(2));
      expect(
        icons.every((i) => i.customIconId == 'art' && i.size == 28),
        isTrue,
      );
      repo.deleteIcon(repo.place.id, 'art');
      await tester.pumpAndSettle();
      expect(find.text('?'), findsNWidgets(2));
    },
  );
  workflowTest(
    'Show on Map centers and names a grouped plant and Back restores unsaved edit fields',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      platform.initialize.complete();
      final repo = await repository();
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Saved name',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51.02, 1.02),
        sectionId: 'row',
      );
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(path: '/edit', builder: (_, _) => EditPlantScreen(plant.id)),
          GoRoute(
            path: '/',
            builder: (_, state) => MapScreen(
              focus: state.extra as Coordinates?,
              focusPlantId: state.uri.queryParameters['plant'],
            ),
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
            rowEndpointSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Plant name'),
        'Unsaved name',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Latitude'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'),
        'invalid draft',
      );
      await tester.scrollUntilVisible(
        find.text('Show on Map'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Show on Map'));
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, const LatLng(51.02, 1.02));
      final marker = map.markers.singleWhere(
        (m) => m.markerId.value == plant.id,
      );
      expect(marker.infoWindow.title, 'Saved name');
      expect(platform.shownNames.last.value, plant.id);
      map.onTap!(const LatLng(51, 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .any((m) => m.markerId.value == plant.id),
        isFalse,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Plant name'))
            .controller!
            .text,
        'Unsaved name',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Latitude'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Latitude'))
            .controller!
            .text,
        'invalid draft',
      );
      expect(repo.plants.single.name, 'Saved name');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  workflowTest(
    'Version History shows installed version plus four prior feature updates',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWith((ref) async => '0.51.0 (51)'),
          ],
          child: const MaterialApp(home: VersionHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 0.51.0'), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Version 0.47.0'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Version 0.47.0'), findsOneWidget);
    },
  );
}
