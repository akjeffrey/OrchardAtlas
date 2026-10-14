import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/add_plant_screen.dart';
import 'package:orchard_atlas/ui/plant_detail_screen.dart';

void main() {
  testWidgets(
    'add another preselects taxonomy but requires a new confirmed location',
    (tester) async {
      final cultivar = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Honeycrisp',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AddPlantScreen(
              template: PlantTemplate(name: 'Row A', taxonId: cultivar.id),
            ),
          ),
        ),
      );
      expect(find.text('Row A'), findsOneWidget);
      expect(find.text('Honeycrisp'), findsOneWidget);
      final textFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(textFields[1].controller!.text, isEmpty);
      expect(textFields[2].controller!.text, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Save plant locally'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save plant locally'));
      await tester.pump();
      expect(find.textContaining('Confirm this plant'), findsOneWidget);
    },
  );
  testWidgets(
    'saving a confirmed plant returns to a map focus and persists its new identity',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeFirebaseFirestore();
      final repo = FirestoreOrchardRepository(
        store,
        await SharedPreferences.getInstance(),
      );
      final place = Place(
        id: 'place',
        name: 'Orchard',
        ownerId: 'u',
        createdAt: DateTime.now(),
      );
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
            builder: (_, state) {
              final focus = state.extra as Coordinates;
              return Scaffold(
                body: Text('Map focus: ${focus.latitude}, ${focus.longitude}'),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => place),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('I confirm this plant’s position'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('I confirm this plant’s position'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Save plant locally'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save plant locally'));
      await tester.pumpAndSettle();
      expect(find.text('Map focus: 51.25, 1.25'), findsOneWidget);
      final saved = (await repo.watchPlants('place').first).value.single;
      expect(saved.name, 'Next apple');
      expect(saved.taxonId, species.id);
      expect(saved.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    },
  );
  testWidgets('changing taxonomy parent clears descendants', (tester) async {
    final cultivar = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Honeycrisp',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AddPlantScreen(
            template: PlantTemplate(name: 'Row A', taxonId: cultivar.id),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fruit trees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Berries').last);
    await tester.pumpAndSettle();
    expect(find.text('Honeycrisp'), findsNothing);
    expect(find.text('Domestic apple'), findsNothing);
    expect(find.text('Species'), findsNothing);
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
      expect(find.text('1.500 kg · 0 count'), findsOneWidget);
      expect(find.textContaining('Pending sync'), findsNWidgets(2));
      expect(find.textContaining('Harvest ·'), findsOneWidget);
      expect(find.text('Add Another Like This'), findsOneWidget);
    },
  );
}
