import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/seed_trays.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/seed_tray_mapping.dart';
import 'package:orchard_atlas/ui/seed_trays_screen.dart';
import 'package:orchard_atlas/ui/seed_tray_viewport.dart';
import 'package:orchard_atlas/ui/icon_picker.dart';

void main() {
  SeedTray tray(String property) => SeedTray(
    id: 'tray',
    propertyId: property,
    name: 'Seeds',
    rows: 2,
    columns: 3,
    createdAt: DateTime(2026),
  );
  Future<LocalTrialRepository> repo() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(LocalTrialRepository r, Widget child) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(r),
      authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
      placeProvider.overrideWith((ref) async => r.place),
    ],
    child: MaterialApp(home: child),
  );
  test(
    'packet icon mapping is optional and transplantation preserves the choice',
    () {
      final t = tray('property');
      final a = TrayAssignment(
        label: 'Apple',
        taxonId: starterTaxonomy.taxa[2].id,
        kind: TrayContentKind.seed,
        assignedAt: DateTime(2026),
        packetFrontId: 'front',
        usePacketFrontIcon: true,
      );
      final map = SeedTrayMapping.cell(t, TrayPosition(1, 1), a);
      expect(SeedTrayMapping.readCell(map).value.usePacketFrontIcon, isTrue);
      map.remove('usePacketFrontIcon');
      expect(SeedTrayMapping.readCell(map).value.usePacketFrontIcon, isFalse);
      expect(a.withTransplantDate('2026-11-27').usePacketFrontIcon, isTrue);
      expect(
        () => TrayAssignment(
          label: 'Apple',
          taxonId: a.taxonId,
          kind: a.kind,
          assignedAt: a.assignedAt,
          usePacketFrontIcon: true,
        ),
        throwsArgumentError,
      );
    },
  );
  testWidgets(
    'zoom buttons, pinch, fit and reset preserve transformed hit testing',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeedTrayViewport(
              contentSize: const Size(1200, 1200),
              child: Stack(
                children: [
                  Positioned(
                    left: 100,
                    top: 100,
                    width: 100,
                    height: 100,
                    child: GestureDetector(
                      key: const ValueKey('test-cell'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                      child: const ColoredBox(color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      double scale() => tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      await tester.tap(find.byTooltip('Zoom in tray'));
      await tester.pumpAndSettle();
      expect(scale(), greaterThan(1));
      await tester.tap(find.byTooltip('Zoom out tray'));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, 0.001));
      final center = tester.getCenter(viewer);
      final one = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final two = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await one.moveTo(center - const Offset(80, 0));
      await two.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
      expect(scale(), greaterThan(1));
      await tester.tap(find.text('Fit tray'));
      await tester.pumpAndSettle();
      expect(scale(), lessThan(1), reason: 'Viewport: ${tester.getSize(viewer)}');
      final rect = tester.getRect(viewer),
          cell = tester.getRect(find.byKey(const ValueKey('test-cell')));
      expect(rect.contains(cell.center), isTrue);
      await tester.tap(find.byKey(const ValueKey('test-cell')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.tap(find.byTooltip('Reset tray zoom'));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, 0.001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'packet cells render cached thumbnails and safely fall back when unavailable',
    (tester) async {
      final r = await repo(), t = tray('local');
      final actual = tray(r.place.id);
      await r.createSeedTray(actual);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      );
      await r.assignTrayCells(
        actual,
        {TrayPosition(1, 1)},
        TrayAssignment(
          label: 'Apple',
          taxonId: starterTaxonomy.taxa[2].id,
          kind: TrayContentKind.seed,
          assignedAt: t.createdAt,
          packetFrontId: 'front',
          usePacketFrontIcon: true,
        ),
        packetPhotos: [
          SeedPacketPhoto(
            id: 'front',
            authorId: r.place.ownerId,
            image: bytes,
            thumbnail: bytes,
          ),
        ],
      );
      await tester.pumpWidget(wrap(r, SeedTrayDetail(actual.id)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(IconPreview), findsNothing);
      final record = (await tester.runAsync(
        () => r.watchRecords(actual.propertyId, RecordKind.photo).first,
      ))!.single;
      await tester.runAsync(
        () => r.putRecord(actual.propertyId, RecordKind.photo, 'front', {
          ...record,
          'thumbnail': '%%%',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(IconPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
