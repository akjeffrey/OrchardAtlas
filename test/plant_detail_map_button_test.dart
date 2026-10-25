import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/plant_detail_screen.dart';

void main() {
  testWidgets(
    'Plant Detail Show on Map uses saved coordinates, selected identity and Back returns to detail',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalTrialRepository.open(
        await SharedPreferences.getInstance(),
      );
      final plant = ManagedPlant(
        id: 'plant',
        propertyId: repo.place.id,
        name: 'Pear 1',
        taxonId: starterTaxonomy.taxa
            .where((t) => t.rank == TaxonRank.species)
            .first
            .id,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
      );
      repo.savePlant(plant);
      String? focus;
      Coordinates? coordinates;
      final router = GoRouter(
        initialLocation: '/plants/plant',
        routes: [
          GoRoute(
            path: '/plants/:id',
            builder: (_, _) => const PlantDetailScreen('plant'),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) {
              focus = state.uri.queryParameters['plant'];
              coordinates = state.extra as Coordinates?;
              return Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Return to detail'),
                ),
              );
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
            userProvider.overrideWith(
              (ref) =>
                  Stream.value(const OrchardUser(LocalTrialRepository.userId)),
            ),
            mapsConfiguredProvider.overrideWithValue(false),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show on Map'));
      await tester.pumpAndSettle();
      expect(focus, 'plant');
      expect(coordinates?.latitude, 51);
      expect(coordinates?.longitude, 1);
      await tester.tap(find.text('Return to detail'));
      await tester.pumpAndSettle();
      expect(find.text('Plant Detail'), findsOneWidget);
      repo.updatePlant(plant.copyWith(status: ItemStatus.archived));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show on Map'));
      await tester.pumpAndSettle();
      expect(
        find.text('Restore this archived plant before showing it on the map.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
