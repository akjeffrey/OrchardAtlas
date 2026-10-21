import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/backup_documents.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/ui/app_version_banner.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/icon_fixture.dart';
import 'support/recording_map_platform.dart';

void main() {
  testWidgets(
    'row endpoints use small centered dots at each zoom and retain labels and selection',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      platform.initialize.complete();
      SharedPreferences.setMockInitialValues({});
      final repo = LocalTrialRepository.open(
        await SharedPreferences.getInstance(),
      );
      final row = OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Apples',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.001)],
        createdAt: DateTime(2026),
      );
      var selections = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            mapsConfiguredProvider.overrideWithValue(true),
            markerSymbolsProvider.overrideWith((ref) async => {}),
            rowEndpointSymbolsProvider.overrideWith(
              (ref) async => {
                true: BitmapDescriptor.bytes(iconPng(), width: 10, height: 10),
                false: BitmapDescriptor.bytes(
                  wideIconPng(),
                  width: 10,
                  height: 10,
                ),
              },
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrchardMap(sections: [row], onSection: (_) => selections++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      for (final zoom in [19.0, 15.0, 10.0, 21.0]) {
        map().onCameraMove!(
          CameraPosition(target: const LatLng(51, 1), zoom: zoom),
        );
        await tester.pumpAndSettle();
        for (final start in [true, false]) {
          final marker = map().markers.singleWhere(
            (m) => m.markerId.value == 'row-${start ? 'start' : 'finish'}-row',
          );
          expect(marker.icon, isA<BytesMapBitmap>());
          final icon = marker.icon as BytesMapBitmap;
          expect(icon.width, rowEndpointSizeForZoom(zoom));
          expect(icon.height, rowEndpointSizeForZoom(zoom));
          expect(icon.width!, lessThan(markerSizeForZoom(zoom)));
          expect(icon.byteData, start ? iconPng() : wideIconPng());
          expect(marker.anchor, const Offset(.5, .5));
          expect(
            marker.position,
            start ? const LatLng(51, 1) : const LatLng(51, 1.001),
          );
          expect(
            marker.infoWindow.title,
            'Apples · ${start ? 'Start (1)' : 'Finish'}',
          );
        }
        expect(map().polylines.single.points, [
          const LatLng(51, 1),
          const LatLng(51, 1.001),
        ]);
      }
      final start = map().markers.singleWhere(
        (m) => m.markerId.value == 'row-start-row',
      );
      start.onTap!();
      await tester.pumpAndSettle();
      expect(selections, 0);
      expect(platform.shownNames.last.value, 'section-label-row');
      start.onTap!();
      await tester.pumpAndSettle();
      expect(selections, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'screen banner uses the installed version without trial wording',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AndroidBackupDocuments.channel,
            (call) async => call.method == 'version' ? '0.49.0 (49)' : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AndroidBackupDocuments.channel, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [trialModeProvider.overrideWithValue(true)],
          child: const MaterialApp(home: Scaffold(body: AppVersionBanner())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('OrchardAtlas 0.49.0 (49) · Saved on this phone'),
        findsOneWidget,
      );
      expect(find.textContaining('TRIAL'), findsNothing);
      expect(find.textContaining('Trial'), findsNothing);
    },
  );
}
