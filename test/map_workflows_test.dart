import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_search.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/ui/map_screen.dart';
import 'package:orchard_atlas/ui/plant_filters.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';
import 'support/recording_map_platform.dart';

class _Addresses implements AddressSearchRepository {
  int calls = 0;
  @override
  Future<List<MapLocation>> search(String query) async {
    calls++;
    return [
      MapLocation('Orchard Road', Coordinates(45, -75)),
      MapLocation('Other orchard', Coordinates(46, -76)),
    ];
  }
}

void main() {
  late GoogleMapsFlutterPlatform previous;
  late RecordingMapPlatform platform;
  late LocalTrialRepository repo;
  late _Addresses addresses;
  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    platform = RecordingMapPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
    addresses = _Addresses();
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = previous);

  Future<void> show(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalTrialRepository.open(await SharedPreferences.getInstance());
    platform.initialize.complete();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trialModeProvider.overrideWithValue(true),
          mapsConfiguredProvider.overrideWithValue(true),
          orchardRepositoryProvider.overrideWithValue(repo),
          placeProvider.overrideWith((ref) async => repo.place),
          addressSearchRepositoryProvider.overrideWithValue(addresses),
          markerSymbolsProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(home: MapScreen(focus: Coordinates(51, 1))),
      ),
    );
    await tester.pumpAndSettle();
    platform.attachPendingViews();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'trial satellite map expands without losing its map, pins or camera',
    (tester) async {
      await show(tester);
      final original = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(original.mapType, MapType.satellite);
      original.onTap!(const LatLng(51.1, 1.1));
      original.onCameraMove!(
        const CameraPosition(target: LatLng(51.2, 1.2), zoom: 18),
      );
      await tester.pumpAndSettle();
      final count = platform.created.length;
      await tester.tap(find.byTooltip('Full screen map'));
      await tester.pumpAndSettle();
      expect(find.byType(PlantFilterBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(platform.created.length, count);
      expect(platform.disposed, isEmpty);
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(51.1, 1.1),
      );
      await tester.tap(find.byTooltip('Data mode'));
      await tester.pumpAndSettle();
      expect(find.byType(PlantFilterBar), findsOneWidget);
      expect(platform.created.length, count);
      expect(platform.disposed, isEmpty);
    },
  );

  testWidgets(
    'row entered on satellite map saves and survives offline restart',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Add row'));
      await tester.pumpAndSettle();
      for (final point in [const LatLng(51, 1), const LatLng(51.001, 1.001)]) {
        tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(point);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Finish drawing'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Area / row name'),
        'Blueberry row',
      );
      await tester.tap(find.text('Save shape'));
      await tester.pumpAndSettle();
      expect(repo.sections.single.kind, SectionKind.row);
      expect(repo.sections.single.vertices.length, 2);
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .polylines
            .single
            .polylineId
            .value,
        repo.sections.single.id,
      );
      await repo
          .watchSections(repo.place.id)
          .firstWhere((s) => !s.hasPendingWrites);
      final restarted = LocalTrialRepository.open(
        await SharedPreferences.getInstance(),
      );
      expect(restarted.sections.single.name, 'Blueberry row');
    },
  );

  testWidgets(
    'area drawing rejects crossed edges and supports undo and discard',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Add area'));
      await tester.pumpAndSettle();
      for (final point in [
        const LatLng(51, 1),
        const LatLng(51.001, 1.001),
        const LatLng(51, 1.001),
        const LatLng(51.001, 1),
      ]) {
        tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(point);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Finish drawing'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Polygon edges cannot intersect'),
        findsOneWidget,
      );
      expect(repo.sections, isEmpty);
      await tester.tap(find.text('Undo vertex'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .polygons
            .single
            .points
            .length,
        3,
      );
      await tester.tap(find.text('Cancel drawing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep drawing'));
      await tester.pumpAndSettle();
      expect(find.text('Finish drawing'), findsOneWidget);
      await tester.tap(find.text('Cancel drawing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.sections, isEmpty);
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isEmpty,
      );
    },
  );

  testWidgets(
    'coordinate search is local and address results require selection',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Search map location'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(
        TextField,
        'Address or latitude, longitude',
      );
      await tester.enterText(field, '91, 0');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Latitude must be'), findsOneWidget);
      expect(addresses.calls, 0);
      await tester.enterText(field, '45.5, -75.5');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(
        platform.cameras.last,
        CameraUpdate.newLatLngZoom(const LatLng(45.5, -75.5), 19).toJson(),
      );
      expect(addresses.calls, 0);
      await tester.tap(find.byTooltip('Search map location'));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Orchard');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(addresses.calls, 1);
      expect(find.text('Other orchard'), findsOneWidget);
      await tester.tap(find.text('Orchard Road'));
      await tester.pumpAndSettle();
      expect(
        platform.cameras.last,
        CameraUpdate.newLatLngZoom(const LatLng(45, -75), 19).toJson(),
      );
    },
  );
}
