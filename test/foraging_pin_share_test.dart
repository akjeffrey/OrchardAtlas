import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/application/extensions.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/map_view_repository.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/find_sharing.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/foraging_screen.dart';
import 'package:orchard_atlas/ui/plant_symbols.dart';

import 'support/recording_map_platform.dart';

class ShareRecorder implements FindSharingRepository {
  final messages = <String>[];
  @override
  Future<void> share(String text) async {
    messages.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('share summary includes the find and usable map link, omitting private notes and account identifiers', () {
    final r = ResourceRecord(
      id: 'private-id',
      orchard: 'private-orchard',
      name: 'Wild pears',
      taxonId: 'taxon',
      location: Coordinates(-41.125, 173.25),
      createdAt: DateTime(2026),
      startMonth: 10,
      endMonth: 2,
      notes: 'Private gate code 1234',
    );
    final text = findShareText(r, classification: 'Fruit trees › Pear');
    expect(text, contains('Wild pears'));
    expect(text, contains('Oct–Feb'));
    expect(text, contains('-41.1250000, 173.2500000'));
    final url = text.split('\n').firstWhere((s) => s.startsWith('https://'));
    expect(Uri.parse(url).queryParameters['query'], '-41.1250000,173.2500000');
    expect(text, isNot(contains('Private gate')));
    expect(text, isNot(contains('private-orchard')));
    expect(text, isNot(contains('private-id')));
  });
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(
    LocalTrialRepository repo,
    Widget child, {
    bool native = false,
    ShareRecorder? share,
  }) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
      placeProvider.overrideWith((ref) async => repo.place),
      mapViewRepositoryProvider.overrideWithValue(
        DeviceMapViewRepository(repo.preferences),
      ),
      mapsConfiguredProvider.overrideWithValue(native),
      trialModeProvider.overrideWithValue(true),
      markerSymbolsProvider.overrideWith((ref) async => {}),
      rowEndpointSymbolsProvider.overrideWith((ref) async => {}),
      if (share != null) findSharingProvider.overrideWithValue(share),
    ],
    child: MaterialApp(home: child),
  );
  Finder dropdown(String label) => find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  Future<void> choose(WidgetTester t, String label, String option) async {
    await t.scrollUntilVisible(
      dropdown(label),
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(dropdown(label));
    await t.pumpAndSettle();
    await t.tap(find.text(option).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'native map pin persists through pan/cancel, dragging changes it and save uses that exact position',
    (tester) async {
      final original = GoogleMapsFlutterPlatform.instance,
          platform = RecordingMapPlatform();
      GoogleMapsFlutterPlatform.instance = platform;
      platform.initialize.complete();
      addTearDown(() => GoogleMapsFlutterPlatform.instance = original);
      final repo = await repository();
      await tester.pumpWidget(wrap(repo, const ForagingScreen(), native: true));
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
      map().onTap!(const LatLng(51.1234, 1.4321));
      await tester.pumpAndSettle();
      Marker selected() => map().markers.singleWhere(
        (m) => m.markerId.value == 'selected-position',
      );
      expect(selected().position, const LatLng(51.1234, 1.4321));
      map().onCameraMove!(
        const CameraPosition(target: LatLng(53, 3), zoom: 16),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add resource'));
      await tester.pumpAndSettle();
      final editor = tester.widget<ResourceEditor>(find.byType(ResourceEditor));
      expect(editor.initialLocation!.latitude, 51.1234);
      expect(editor.initialLocation!.longitude, 1.4321);
      Navigator.of(tester.element(find.byType(ResourceEditor))).pop();
      await tester.pumpAndSettle();
      expect(selected().position, const LatLng(51.1234, 1.4321));
      selected().onDragEnd!(const LatLng(51.2345, 1.5432));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add resource'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Resource name'),
        'Shared pear',
      );
      await choose(tester, 'Group', 'Fruit trees');
      await choose(tester, 'Type', 'Apple (Malus)');
      await choose(tester, 'Variety', 'Domestic apple');
      await tester.scrollUntilVisible(
        find.text('Save resource'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save resource'));
      await tester.pumpAndSettle();
      platform.attachPendingViews();
      await tester.pumpAndSettle();
      expect(find.byType(ResourceEditor), findsNothing);
      expect(
        map().markers.any((m) => m.markerId.value == 'selected-position'),
        isFalse,
      );
      final records = await tester.runAsync(
        () => repo.watchRecords(repo.place.id, RecordKind.foraging).first,
      );
      final saved = ResourceRecord.read(repo.place.id, records!.single);
      expect(saved.location.latitude, 51.2345);
      expect(saved.location.longitude, 1.5432);
      expect(saved.public, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Share find is available in the local build and sends a deliberate location summary',
    (tester) async {
      final repo = await repository(), share = ShareRecorder();
      final r = ResourceRecord(
        id: 'r',
        orchard: repo.place.id,
        name: 'Wild apples',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
        notes: 'Do not include this note',
      );
      await repo.putRecord(repo.place.id, RecordKind.foraging, r.id, r.toMap());
      await tester.pumpWidget(wrap(repo, ResourceDetail(r), share: share));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Share find'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Share find'));
      await tester.pumpAndSettle();
      expect(share.messages, hasLength(1));
      expect(share.messages.single, contains('Wild apples'));
      expect(share.messages.single, contains('google.com/maps'));
      expect(
        share.messages.single,
        isNot(contains('Do not include this note')),
      );
      final records = await tester.runAsync(
        () => repo.watchRecords(repo.place.id, RecordKind.foraging).first,
      );
      expect(records!.single['public'], isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
