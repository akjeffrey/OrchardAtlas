import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/icon_library_screen.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';
import 'package:orchard_atlas/ui/settings_screen.dart';

import 'support/icon_fixture.dart';
import 'support/recording_map_platform.dart';

class _Importer implements IconImporter {
  Uint8List? bytes = iconPng();
  bool fail = false;
  @override
  Future<Uint8List?> importPng() async {
    if (fail) throw StateError('Invalid image');
    return bytes;
  }
}

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(LocalTrialRepository repo, Widget child, {_Importer? importer}) =>
      ProviderScope(
        overrides: [
          orchardRepositoryProvider.overrideWithValue(repo),
          placeProvider.overrideWith((ref) async => repo.place),
          if (importer != null)
            iconImporterProvider.overrideWithValue(importer),
        ],
        child: MaterialApp(home: child),
      );
  testWidgets(
    'settings edits a stable variety ID, selecting custom artwork, and cancel is safe',
    (tester) async {
      final repo = await repository();
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'icon', name: 'Uploaded pear', png: iconPng()),
      );
      final variety = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Domestic apple',
      );
      await tester.pumpWidget(wrap(repo, const ClassificationSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find Group, Type or Variety'),
        'Domestic apple',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Domestic apple'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Option name'),
        'Cancelled name',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.taxa, isEmpty);
      await tester.tap(find.widgetWithText(ListTile, 'Domestic apple'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Option name'),
        'Home apple variety',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uploaded pear').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save option'));
      await tester.pumpAndSettle();
      expect(repo.taxa.single.id, variety.id);
      expect(repo.taxa.single.name, 'Home apple variety');
      expect(repo.taxa.single.customIconId, 'icon');
      expect(repo.taxa.single.iconOverride, isTrue);
      expect(find.text('Option saved'), findsOneWidget);
    },
  );
  testWidgets(
    'icon import can cancel, reports failure, and saves selected bytes',
    (tester) async {
      final repo = await repository();
      final importer = _Importer()..bytes = null;
      await tester.pumpWidget(
        wrap(repo, const IconLibraryScreen(), importer: importer),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import image'));
      await tester.pumpAndSettle();
      expect(repo.icons, isEmpty);
      importer.fail = true;
      await tester.tap(find.text('Import image'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not import icon:'), findsOneWidget);
      importer.fail = false;
      importer.bytes = iconPng();
      await tester.tap(find.text('Import image'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Imported tree');
      await tester.tap(find.text('Save icon'));
      await tester.pumpAndSettle();
      expect(repo.icons.single.name, 'Imported tree');
      expect(repo.icons.single.png, iconPng());
      expect(find.text('Imported tree'), findsOneWidget);
    },
  );
  testWidgets(
    'plant and Area icons stay bounded and shrink as native map zooms out',
    (tester) async {
      final old = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = old);
      platform.initialize.complete();
      final repo = await repository();
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'icon', name: 'Custom marker', png: wideIconPng()),
      );
      final variety = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Domestic apple',
      );
      repo.saveTaxon(
        repo.place.id,
        Taxon(
          id: variety.id,
          name: variety.name,
          rank: variety.rank,
          parentId: variety.parentId,
          symbol: variety.symbol,
          customIconId: 'icon',
          iconOverride: true,
        ),
      );
      final plant = ManagedPlant(
        id: 'plant',
        propertyId: repo.place.id,
        name: 'Tree',
        taxonId: variety.id,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
      );
      final area = OrchardSection(
        id: 'area',
        propertyId: repo.place.id,
        name: 'Area',
        kind: SectionKind.area,
        vertices: [
          Coordinates(51, 1),
          Coordinates(51, 1.01),
          Coordinates(51.01, 1),
        ],
        createdAt: DateTime(2026),
        customIconId: 'icon',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
            mapsConfiguredProvider.overrideWithValue(true),
            markerSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrchardMap(plants: [plant], sections: [area]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      for (final entry in [
        (19.0, 28.0),
        (15.0, 22.0),
        (10.0, 16.0),
        (21.0, 28.0),
      ]) {
        map().onCameraMove!(
          CameraPosition(target: const LatLng(51, 1), zoom: entry.$1),
        );
        await tester.pumpAndSettle();
        for (final marker in map().markers) {
          final bitmap = marker.icon as BytesMapBitmap;
          expect(bitmap.width, entry.$2);
          expect(bitmap.height, entry.$2 / 2);
          expect(bitmap.byteData, wideIconPng());
        }
        expect(map().polygons.single.points, hasLength(3));
      }
      expect(platform.created, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
