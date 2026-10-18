import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/backup_service.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/ui/backup_screen.dart';
import 'package:orchard_atlas/ui/icon_library_screen.dart';
import 'package:orchard_atlas/ui/icon_picker.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/icon_fixture.dart';
import 'support/recording_map_platform.dart';

class Documents implements BackupDocuments {
  Documents(this.contents);
  final String contents;
  int writes = 0;
  @override
  Future<String?> create() async => null;
  @override
  Future<String?> select() async => 'content://restored-file';
  @override
  Future<String> read(String document) async => contents;
  @override
  Future<void> retainForBackup(String document) async {}
  @override
  Future<void> write(String document, String contents) async {
    writes++;
  }

  @override
  Future<void> delete(String document) async {}
}

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  testWidgets(
    'restore offers automatic backup with the choice enabled by default',
    (tester) async {
      final repo = await repository();
      final store = TrialBackupStore(repo.preferences, repo);
      final docs = Documents(await store.export());
      final service = BackupService(store, docs);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backupServiceProvider.overrideWith((ref) => service)],
          child: const MaterialApp(home: BackupScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore from Drive or a backup file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      // Restore stays busy while the destination question is open, so its
      // progress indicator deliberately keeps animating behind this dialog.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Use this file for automatic backups?'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Use restored file'),
            )
            .value,
        isTrue,
      );
      expect(service.connected, isFalse);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        repo.preferences.getString(BackupService.documentKey),
        'content://restored-file',
      );
      expect(docs.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'delete icon confirms usage, cancel keeps it, deletion renders a question mark',
    (tester) async {
      final repo = await repository();
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'custom', name: 'Apple art', png: iconPng()),
      );
      final type = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'Apple (Malus)',
      );
      repo.saveTaxon(
        repo.place.id,
        Taxon(
          id: type.id,
          name: type.name,
          rank: type.rank,
          parentId: type.parentId,
          symbol: type.symbol,
          customIconId: 'custom',
          iconOverride: true,
        ),
      );
      final plant = OrchardCommands(repo, orchardTaxonomy(repo.taxa)).addPlant(
        place: repo.place,
        name: 'Apple',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
          ],
          child: const MaterialApp(home: IconLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Apple art'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Used by 1 plants'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.icons.single.deleted, isFalse);
      await tester.tap(find.byTooltip('Delete Apple art'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete icon'));
      await tester.pumpAndSettle();
      expect(find.text('No custom icons yet.'), findsOneWidget);
      expect(repo.icons.single.deleted, isTrue);
      expect(repo.plants.single.id, plant.id);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: IconPreview(
                symbol: PlantSymbol.apple,
                customIconId: 'custom',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('?'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'Area and Row first taps show anchored native names; second taps open the section',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      final platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      platform.initialize.complete();
      final repo = await repository();
      final row = OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Blueberries',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51, 1.01)],
        createdAt: DateTime(2026),
      );
      final area = OrchardSection(
        id: 'area',
        propertyId: repo.place.id,
        name: 'Raspberries',
        kind: SectionKind.area,
        vertices: [
          Coordinates(51, 1),
          Coordinates(51, 1.01),
          Coordinates(51.01, 1),
        ],
        createdAt: DateTime(2026),
      );
      final opened = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            mapsConfiguredProvider.overrideWithValue(true),
            markerSymbolsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrchardMap(sections: [row, area], onSection: opened.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      map().polygons.single.onTap!();
      await tester.pumpAndSettle();
      expect(platform.shownNames.last.value, 'section-label-area');
      expect(opened, isEmpty);
      final label = map().markers.singleWhere(
        (m) => m.markerId.value == 'section-label-area',
      );
      expect(label.infoWindow.title, 'Raspberries');
      expect(
        label.position,
        LatLng(sectionCenter(area).latitude, sectionCenter(area).longitude),
      );
      expect(find.byType(Card), findsNothing);
      map().onCameraMove!(
        const CameraPosition(target: LatLng(52, 2), zoom: 14),
      );
      await tester.pumpAndSettle();
      expect(
        map().markers.singleWhere((m) => m.markerId == label.markerId).position,
        label.position,
      );
      map().polylines.single.onTap!();
      await tester.pumpAndSettle();
      expect(platform.shownNames.last.value, 'section-label-row');
      expect(opened, isEmpty);
      map().markers
          .singleWhere((m) => m.markerId.value == 'section-label-row')
          .infoWindow
          .onTap!();
      await tester.pumpAndSettle();
      expect(opened, ['row']);
      map().polygons.single.onTap!();
      map().onTap!(const LatLng(51, 1));
      map().polygons.single.onTap!();
      await tester.pumpAndSettle();
      expect(opened, ['row']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('deleted custom marker uses the bounded question-mark bitmap', (
    tester,
  ) async {
    final previous = GoogleMapsFlutterPlatform.instance;
    final platform = RecordingMapPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
    addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
    platform.initialize.complete();
    final repo = await repository();
    repo.saveIcon(
      repo.place.id,
      MapIcon(id: 'custom', name: 'Apple art', png: iconPng()),
    );
    final variety = starterTaxonomy.taxa[2];
    repo.saveTaxon(
      repo.place.id,
      Taxon(
        id: variety.id,
        name: variety.name,
        rank: variety.rank,
        parentId: variety.parentId,
        symbol: variety.symbol,
        customIconId: 'custom',
        iconOverride: true,
      ),
    );
    repo.deleteIcon(repo.place.id, 'custom');
    final plant = OrchardCommands(repo, orchardTaxonomy(repo.taxa)).addPlant(
      place: repo.place,
      name: 'Apple',
      taxonId: variety.id,
      location: Coordinates(51, 1),
    );
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orchardRepositoryProvider.overrideWithValue(repo),
          placeProvider.overrideWith((ref) async => repo.place),
          mapsConfiguredProvider.overrideWithValue(true),
          markerSymbolsProvider.overrideWith(
            (ref) async => {
              PlantSymbol.unknown: BitmapDescriptor.bytes(
                bytes,
                width: 28,
                height: 28,
              ),
            },
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: OrchardMap(plants: [plant])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    final bitmap = map.markers.single.icon as BytesMapBitmap;
    expect(bitmap.byteData, bytes);
    expect(bitmap.width, 28);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
