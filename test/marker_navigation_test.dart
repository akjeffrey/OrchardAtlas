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
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/layout_canvas.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/recording_map_platform.dart';

void main() {
  for (final native in [true, false]) {
    testWidgets('two-tap plant navigation and resets, native=$native', (
      tester,
    ) async {
      final oldPlatform = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = oldPlatform);
      platform.initialize.complete();
      SharedPreferences.setMockInitialValues({});
      final repo = LocalTrialRepository.open(
        await SharedPreferences.getInstance(),
      );
      ManagedPlant plant(String id, double latitude) => ManagedPlant(
        id: id,
        propertyId: repo.place.id,
        name: 'Plant $id',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(latitude, 1),
        createdAt: DateTime(2026),
      );
      final a = plant('A', 51), b = plant('B', 51.0001);
      final plants = ValueNotifier([a, b]);
      addTearDown(plants.dispose);
      var navigations = 0;
      var backgroundTaps = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: ValueListenableBuilder<List<ManagedPlant>>(
                valueListenable: plants,
                builder: (_, items, _) => OrchardMap(
                  plants: items,
                  center: a.location,
                  onTap: (_) => backgroundTaps++,
                  onPlant: (id) {
                    navigations++;
                    context.push('/plants/$id');
                  },
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/plants/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Detail ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            mapsConfiguredProvider.overrideWithValue(native),
            markerSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      if (native) {
        platform.attachPendingViews();
        await tester.pumpAndSettle();
      }
      Future<void> tapPlant(String id) async {
        if (native) {
          final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
          final marker = map.markers.singleWhere((m) => m.markerId.value == id);
          expect(marker.consumeTapEvents, isTrue);
          expect(marker.infoWindow.onTap, isNull);
          marker.onTap!();
        } else {
          await tester.tap(find.byTooltip('Plant $id'));
        }
        await tester.pumpAndSettle();
      }

      Future<void> background() async {
        if (native) {
          tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(
            const LatLng(51, 1),
          );
        } else {
          tester.widget<LayoutCanvas>(find.byType(LayoutCanvas)).onTap!(
            a.location,
          );
        }
        await tester.pumpAndSettle();
      }

      await tapPlant('A');
      expect(find.text('Plant A'), findsOneWidget);
      expect(navigations, 0);
      await tapPlant('B');
      expect(find.text('Plant A'), findsNothing);
      expect(find.text('Plant B'), findsOneWidget);
      expect(navigations, 0);
      await tapPlant('A');
      expect(navigations, 0);
      await background();
      expect(backgroundTaps, 1);
      expect(find.text('Plant A'), findsNothing);
      await tapPlant('A');
      expect(navigations, 0);
      await tapPlant('A');
      expect(find.text('Detail A'), findsOneWidget);
      expect(navigations, 1);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Plant A'), findsNothing);
      await tapPlant('B');
      plants.value = [a];
      await tester.pumpAndSettle();
      expect(find.text('Plant B'), findsNothing);
      plants.value = [a, b];
      await tester.pumpAndSettle();
      await tapPlant('B');
      expect(navigations, 1);
      await tapPlant('B');
      expect(find.text('Detail B'), findsOneWidget);
      expect(navigations, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
