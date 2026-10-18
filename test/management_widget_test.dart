import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/tasks_screen.dart';
import 'package:orchard_atlas/ui/edit_plant_screen.dart';

void managementWidgetTest(
  String name,
  Future<void> Function(WidgetTester) body,
) => testWidgets(name, body, timeout: const Timeout(Duration(minutes: 1)));

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Widget wrap(LocalTrialRepository repo, Widget child) => ProviderScope(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      placeProvider.overrideWith((ref) async => repo.place),
      trialModeProvider.overrideWithValue(true),
    ],
    child: child,
  );
  managementWidgetTest(
    'task completion persists and remains visible under completed filter',
    (tester) async {
      final repo = await repository();
      repo.saveTask(
        OrchardTask(
          id: 'task',
          propertyId: repo.place.id,
          title: 'Prune orchard',
          createdAt: DateTime.utc(2026),
        ),
      );
      await tester.pumpWidget(
        wrap(repo, const MaterialApp(home: Scaffold(body: TasksPane()))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prune orchard'), findsOneWidget);
      await tester.tap(find.byTooltip('Change task status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      expect(repo.tasks.single.status, TaskStatus.completed);
      expect(find.text('Prune orchard'), findsNothing);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('completed').last);
      await tester.pumpAndSettle();
      expect(find.text('Prune orchard'), findsOneWidget);
    },
  );
  managementWidgetTest('task form saves a targeted task without a due date', (
    tester,
  ) async {
    final repo = await repository();
    final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
      place: repo.place,
      name: 'Apple 12',
      taxonId: starterTaxonomy.taxa[2].id,
      location: Coordinates(51, 1),
    );
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, _) => TaskFormScreen(itemId: plant.id),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Task saved')),
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
      'Fertilize',
    );
    await tester.scrollUntilVisible(
      find.text('Save task'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.title, 'Fertilize');
    expect(repo.tasks.single.itemId, plant.id);
    expect(repo.tasks.single.dueDate, isNull);
    expect(find.text('Task saved'), findsOneWidget);
  });
  managementWidgetTest(
    'metadata editor preserves planting history and archived status',
    (tester) async {
      final repo = await repository();
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Apple',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
        plantingDate: DateTime(2022, 4, 10),
        authorId: LocalTrialRepository.userId,
      );
      repo.updatePlant(plant.copyWith(status: ItemStatus.archived));
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(path: '/edit', builder: (_, _) => EditPlantScreen(plant.id)),
          GoRoute(
            path: '/plants/:id',
            builder: (_, _) => const Scaffold(body: Text('Changes saved')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(repo, MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Plant name'),
        'Apple 12',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Rootstock'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Rootstock'),
        'M.111',
      );
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repo.plants.single.name, 'Apple 12');
      expect(repo.plants.single.rootstock, 'M.111');
      expect(repo.plants.single.status, ItemStatus.archived);
      expect(repo.events.single.activityDate, '2022-04-10');
      expect(find.text('Changes saved'), findsOneWidget);
    },
  );
}
