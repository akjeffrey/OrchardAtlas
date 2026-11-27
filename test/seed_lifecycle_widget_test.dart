import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/application/extensions.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/seed_trays.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/ui/seed_trays_screen.dart';

class PacketCamera implements CameraRepository {
  int calls = 0;
  @override
  Future<CapturedPhoto?> capture({required bool camera}) async {
    calls++;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
    );
    return CapturedPhoto(bytes, bytes);
  }
}

void main() {
  Future<(LocalTrialRepository, SeedTray)> setup() async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalTrialRepository.open(
      await SharedPreferences.getInstance(),
    );
    final t = SeedTray(
      id: 'tray',
      propertyId: repo.place.id,
      name: 'Spring tray',
      rows: 1,
      columns: 2,
      createdAt: DateTime(2026),
    );
    await repo.createSeedTray(t);
    await repo.assignTrayCells(
      t,
      {TrayPosition(1, 1)},
      TrayAssignment(
        label: 'Tomato',
        taxonId: starterTaxonomy.taxa[2].id,
        kind: TrayContentKind.seed,
        assignedAt: DateTime(2026),
        plantedOn: '2026-01-01',
      ),
    );
    return (repo, t);
  }

  Widget wrap(
    LocalTrialRepository repo,
    Widget child, {
    PacketCamera? camera,
  }) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
      placeProvider.overrideWith((ref) async => repo.place),
      if (camera != null) cameraProvider.overrideWithValue(camera),
    ],
    child: MaterialApp(home: child),
  );
  testWidgets(
    'recorded transplantation grays the cell and undo restores its growing state',
    (tester) async {
      final (repo, t) = await setup();
      await tester.pumpWidget(wrap(repo, SeedTrayDetail(t.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tray-cell-1-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record transplant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Material && w.color == Colors.grey.shade300,
        ),
        findsOneWidget,
      );
      final cells = await tester.runAsync(
        () => repo.watchTrayCells(t.propertyId, t.id).first,
      );
      expect(cells![TrayPosition(1, 1)]!.isTransplanted, isTrue);
      await tester.tap(find.byKey(const ValueKey('tray-cell-1-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo transplant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Material && w.color == Colors.grey.shade300,
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'packet capture persists front/back only when a planting is applied and deletion is confirmed',
    (tester) async {
      final (repo, t) = await setup();
      final camera = PacketCamera();
      await tester.pumpWidget(wrap(repo, SeedTrayDetail(t.id), camera: camera));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tray-cell-1-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add seed / plant'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Days until transplant (optional)'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Days until transplant (optional)'),
        '14',
      );
      await tester.pumpAndSettle();
      expect(find.text('Expected transplant date: 2026-01-15'), findsOneWidget);
      for (final side in ['front', 'back']) {
        await tester.scrollUntilVisible(
          find.text('Take $side photo'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Take $side photo'));
        await tester.pumpAndSettle();
      }
      expect(camera.calls, 2);
      await tester.scrollUntilVisible(
        find.text('Use packet front photo as cell icon'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Use packet front photo as cell icon'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Apply to selected cells'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Apply to selected cells'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final cells = await tester.runAsync(
        () => repo.watchTrayCells(t.propertyId, t.id).first,
      );
      expect(cells![TrayPosition(1, 1)]!.packetFrontId, isNotNull);
      expect(cells[TrayPosition(1, 1)]!.usePacketFrontIcon, isTrue);
      expect(find.byType(Image), findsOneWidget);
      expect(cells[TrayPosition(1, 1)]!.packetBackId, isNotNull);
      expect(
        await tester.runAsync(
          () => repo.watchRecords(t.propertyId, RecordKind.photo).first,
        ),
        hasLength(2),
      );
      await tester.tap(find.byTooltip('Delete tray'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Spring tray'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete tray'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete tray'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => repo.watchSeedTrays(t.propertyId).first),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repo.watchRecords(t.propertyId, RecordKind.photo).first,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
