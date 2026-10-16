import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/landscape.dart';
import 'package:orchard_atlas/domain/repositories.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/ui/sections_screen.dart';
import 'package:orchard_atlas/ui/crops_screen.dart';
import 'package:orchard_atlas/ui/tasks_screen.dart';

class _Gps implements LocationRepository {
  @override
  Future<LocationFix> currentPosition() async =>
      LocationFix(Coordinates(51, 1), 4);
  @override
  Future<void> openSettings() async {}
}

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(LocalTrialRepository repo, Widget child) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      placeProvider.overrideWith((ref) async => repo.place),
      locationRepositoryProvider.overrideWithValue(_Gps()),
      trialModeProvider.overrideWithValue(true),
    ],
    child: child,
  );
  testWidgets('group checklist completes and skips members independently', (
    tester,
  ) async {
    final repo = await repository();
    final commands = OrchardCommands(repo, starterTaxonomy);
    final taxon = starterTaxonomy.taxa.firstWhere(
      (t) => t.name == 'Domestic apple',
    );
    for (var i = 0; i < 2; i++) {
      commands.addPlant(
        place: repo.place,
        name: 'Apple $i',
        taxonId: taxon.id,
        location: Coordinates(51, 1),
      );
    }
    var serial = 0;
    final group = groupPlantTasks(
      propertyId: repo.place.id,
      title: 'Prune apples',
      plants: repo.plants,
      taxonomy: starterTaxonomy,
      sections: [],
      newId: () => 'id-${++serial}',
    );
    repo.saveTaskGroup(group);
    await tester.pumpWidget(
      wrap(repo, MaterialApp(home: TaskGroupScreen(group.first.groupId!))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change task status').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 of 2 completed · 1 remaining'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Change task status').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 of 2 completed · 0 remaining'),
      findsOneWidget,
    );
    expect(repo.tasks.first.completedOn, calendarDate(DateTime.now()));
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('task form creates one group for all apple descendants', (
    tester,
  ) async {
    final repo = await repository();
    final commands = OrchardCommands(repo, starterTaxonomy);
    for (final name in ['Honeycrisp', 'Gala', 'European pear']) {
      commands.addPlant(
        place: repo.place,
        name: name,
        taxonId: starterTaxonomy.taxa.firstWhere((t) => t.name == name).id,
        location: Coordinates(51, 1),
      );
    }
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(path: '/new', builder: (_, _) => const TaskFormScreen()),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Saved group')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      wrap(repo, MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Task title'),
      'Prune apples',
    );
    await tester.tap(find.text('Whole property').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group: all matching plants').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All classifications'));
    await tester.tap(find.text('All classifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fruit trees › Apple (Malus)').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create group checklist'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Create group checklist'));
    await tester.pumpAndSettle();
    expect(repo.tasks.length, 2);
    expect(repo.tasks.map((t) => t.groupId).toSet().length, 1);
    expect(find.text('Saved group'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets(
    'replanting creates a new season without replacing the old variety',
    (tester) async {
      final repo = await repository();
      final section = OrchardSection(
        id: 'row',
        propertyId: repo.place.id,
        name: 'Garlic row A',
        kind: SectionKind.row,
        vertices: [Coordinates(51, 1), Coordinates(51.001, 1)],
        createdAt: DateTime.utc(2026),
      );
      repo.saveSection(section);
      final crop = CropPlanting(
        id: 'old',
        propertyId: repo.place.id,
        sectionId: 'row',
        taxonId: starterTaxonomy.taxa.firstWhere((t) => t.name == 'Garlic').id,
        label: 'German Extra Hardy',
        season: '2025',
        createdAt: DateTime.utc(2025),
      );
      repo.saveCrop(crop);
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) => CropFormScreen(source: crop),
          ),
          GoRoute(
            path: '/crops/:id',
            builder: (_, _) => const Scaffold(body: Text('Saved season')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(repo, MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Season / year'),
        '2027',
      );
      await tester.scrollUntilVisible(
        find.text('Save planting'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save planting'));
      await tester.pumpAndSettle();
      expect(repo.crops.map((c) => c.season), ['2025', '2027']);
      expect(repo.crops.last.id, isNot(crop.id));
      expect(find.text('Saved season'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
  testWidgets('coordinate editor saves an area polygon', (tester) async {
    final repo = await repository();
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(path: '/new', builder: (_, _) => const SectionFormScreen()),
        GoRoute(
          path: '/sections/:id',
          builder: (_, _) => const Scaffold(body: Text('Saved area')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      wrap(repo, MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Area / row name'),
      'Raspberry patch',
    );
    for (final pair in [
      ['51', '1'],
      ['51.001', '1'],
      ['51.001', '1.001'],
    ]) {
      await tester.scrollUntilVisible(
        find.text('Enter coordinate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Enter coordinate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        pair[0],
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        pair[1],
      );
      await tester.tap(find.text('Use vertex'));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Save area / row'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save area / row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save area / row'));
    await tester.pumpAndSettle();
    expect(repo.sections.single.vertices.length, 3);
    expect(find.text('Saved area'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets(
    'group task form creates a separate checklist member for each garlic row',
    (tester) async {
      final repo = await repository();
      final now = DateTime.utc(2026);
      repo.saveSection(
        OrchardSection(
          id: 'bed',
          propertyId: repo.place.id,
          name: 'Garlic bed',
          kind: SectionKind.area,
          vertices: [
            Coordinates(51, 1),
            Coordinates(51.001, 1),
            Coordinates(51.001, 1.001),
          ],
          createdAt: now,
        ),
      );
      for (final id in ['row-a', 'row-b']) {
        repo.saveSection(
          OrchardSection(
            id: id,
            propertyId: repo.place.id,
            name: id,
            kind: SectionKind.row,
            parentId: 'bed',
            vertices: [Coordinates(51, 1), Coordinates(51.001, 1)],
            createdAt: now,
          ),
        );
      }
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(path: '/new', builder: (_, _) => const TaskFormScreen()),
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Saved rows')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(repo, MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Harvest garlic',
      );
      await tester.tap(find.text('Whole property').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group: areas / rows').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create group checklist'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create group checklist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create group checklist'));
      await tester.pumpAndSettle();
      expect(repo.tasks.map((t) => t.sectionId).toSet(), {'row-a', 'row-b'});
      expect(find.text('Saved rows'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
