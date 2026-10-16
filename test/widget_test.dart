import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/add_plant_screen.dart';
import 'package:orchard_atlas/ui/plant_detail_screen.dart';

class TrialLocation implements LocationRepository {
  int calls = 0;
  @override
  Future<LocationFix> currentPosition() async =>
      LocationFix(Coordinates(51 + (++calls) / 100, 1), 4);
  @override
  Future<void> openSettings() async {}
}

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(LocalTrialRepository repo, TrialLocation gps, Widget child) =>
      ProviderScope(
        overrides: [
          orchardRepositoryProvider.overrideWithValue(repo),
          locationRepositoryProvider.overrideWithValue(gps),
          userProvider.overrideWith(
            (ref) =>
                Stream.value(const OrchardUser(LocalTrialRepository.userId)),
          ),
          placeProvider.overrideWith((ref) async => repo.place),
        ],
        child: child,
      );
  Future<void> select(WidgetTester tester, String current, String next) async {
    await tester.ensureVisible(find.text(current).first);
    await tester.tap(find.text(current).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(next).last);
    await tester.pumpAndSettle();
  }

  Future<String> plantName(WidgetTester tester) async {
    final field = find.byKey(const ValueKey('plant-name'));
    await tester.scrollUntilVisible(
      field,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    return tester.widget<TextField>(field).controller!.text;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Save plant locally'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save plant locally'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plant locally'));
    await tester.pumpAndSettle();
  }

  testWidgets('new planting date defaults to today and can be cleared', (
    tester,
  ) async {
    final repo = await repository();
    await tester.pumpWidget(
      wrap(repo, TrialLocation(), const MaterialApp(home: AddPlantScreen())),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Clear planting date'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(calendarDate(DateTime.now())), findsOneWidget);
    await tester.tap(find.byTooltip('Clear planting date'));
    await tester.pumpAndSettle();
    expect(find.text('Not recorded'), findsOneWidget);
  });
  testWidgets(
    'name follows taxonomy until customized and clearing restores defaults',
    (tester) async {
      final repo = await repository();
      await tester.pumpWidget(
        wrap(repo, TrialLocation(), const MaterialApp(home: AddPlantScreen())),
      );
      await tester.pumpAndSettle();
      await select(tester, 'Group', '🌳 Fruit trees');
      expect(await plantName(tester), 'Fruit trees');
      await select(tester, 'Genus', '🍐 Pear (Pyrus)');
      expect(await plantName(tester), 'Pear (Pyrus)');
      await tester.enterText(
        find.byKey(const ValueKey('plant-name')),
        'My pear',
      );
      await select(tester, 'Species', '🍐 European pear');
      expect(await plantName(tester), 'My pear');
      await tester.enterText(find.byKey(const ValueKey('plant-name')), '');
      await select(tester, '🍐 Pear (Pyrus)', '🍎 Apple (Malus)');
      expect(await plantName(tester), 'Apple (Malus)');
      expect(find.text('🍐 European pear'), findsNothing);
    },
  );
  testWidgets(
    'bulk entry uses fresh GPS, asks after saving, and preserves taxonomy',
    (tester) async {
      final repo = await repository();
      final gps = TrialLocation();
      final species = starterTaxonomy.taxa.firstWhere(
        (t) => t.rank == TaxonRank.species,
      );
      await tester.pumpWidget(
        wrap(
          repo,
          gps,
          MaterialApp(
            home: AddPlantScreen(
              template: PlantTemplate(
                name: 'Row A',
                taxonId: species.id,
                plantedOn: '2020-04-10',
                rootstock: 'M.111',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gps.calls, 1);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Planting date (optional)'), findsOneWidget);
      await save(tester);
      expect(find.text('Plant added'), findsOneWidget);
      expect(repo.plants.single.location.latitude, 51.01);
      await tester.tap(find.text('Add another'));
      await tester.pumpAndSettle();
      expect(gps.calls, 2);
      expect(repo.plants.length, 1);
      await save(tester);
      expect(repo.plants.length, 2);
      expect(repo.events.length, 2);
      expect(
        repo.events.every(
          (e) =>
              e.type == ActivityType.planting && e.activityDate == '2020-04-10',
        ),
        isTrue,
      );
      expect(
        repo.plants.every(
          (p) => p.plantedOn == '2020-04-10' && p.rootstock == 'M.111',
        ),
        isTrue,
      );
      expect(repo.plants.last.location.latitude, 51.02);
      expect(repo.plants.last.taxonId, species.id);
      expect(repo.plants.last.id, isNot(repo.plants.first.id));
    },
  );
  testWidgets(
    'explicit map location is retained and back to map focuses the saved plant',
    (tester) async {
      final repo = await repository();
      final gps = TrialLocation();
      final species = starterTaxonomy.taxa.firstWhere(
        (t) => t.rank == TaxonRank.species,
      );
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) => AddPlantScreen(
              template: PlantTemplate(name: 'Next apple', taxonId: species.id),
              location: Coordinates(51.25, 1.25),
            ),
          ),
          GoRoute(
            path: '/',
            builder: (_, state) => Scaffold(
              body: Text('Map focus: ${(state.extra as Coordinates).latitude}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(repo, gps, MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      expect(gps.calls, 0);
      await save(tester);
      await tester.tap(find.text('Back to map'));
      await tester.pumpAndSettle();
      expect(find.text('Map focus: 51.25'), findsOneWidget);
    },
  );
  testWidgets('dropdown can create and select an option with a chosen icon', (
    tester,
  ) async {
    final repo = await repository();
    await tester.pumpWidget(
      wrap(repo, TrialLocation(), const MaterialApp(home: AddPlantScreen())),
    );
    await tester.pumpAndSettle();
    await select(tester, 'Group', '+ Add new option…');
    await tester.enterText(
      find.widgetWithText(TextField, 'Option name'),
      'Trial nut trees',
    );
    await select(tester, '🌳 tree', '🌰 nut');
    await tester.tap(find.text('Add option'));
    await tester.pumpAndSettle();
    expect(repo.taxa.single.name, 'Trial nut trees');
    expect(repo.taxa.single.symbol, PlantSymbol.nut);
    expect(find.text('🌰 Trial nut trees'), findsOneWidget);
    expect(await plantName(tester), 'Trial nut trees');
  });
  testWidgets(
    'detail renders pending status, derived harvest totals and history',
    (tester) async {
      final now = DateTime.now();
      final plant = ManagedPlant(
        id: 'p',
        propertyId: 'place',
        name: 'Apple 1',
        taxonId: starterTaxonomy.taxa
            .firstWhere((t) => t.rank == TaxonRank.species)
            .id,
        location: Coordinates(51, 1),
        createdAt: now,
      );
      final event = PlantEvent(
        id: 'e',
        propertyId: 'place',
        itemId: 'p',
        authorId: 'u',
        type: ActivityType.harvest,
        occurredAt: now,
        activityDate: calendarDate(now),
        recordedAt: now,
        harvest: Harvest(1500, HarvestUnit.g),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plantsProvider.overrideWith(
              (ref) => Stream.value(
                RepositorySnapshot(
                  [plant],
                  isFromCache: true,
                  hasPendingWrites: true,
                ),
              ),
            ),
            eventsProvider('p').overrideWith(
              (ref) => Stream.value(
                RepositorySnapshot(
                  [event],
                  isFromCache: true,
                  hasPendingWrites: true,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: PlantDetailScreen('p')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Apple 1'), findsOneWidget);
      expect(find.text('1500.000 g'), findsOneWidget);
      expect(find.textContaining('Pending sync'), findsNWidgets(2));
      expect(find.textContaining('Harvest ·'), findsOneWidget);
      expect(find.text('Add Another Like This'), findsOneWidget);
    },
  );
}
