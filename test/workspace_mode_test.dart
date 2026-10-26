import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/application/workspaces.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/map_view_repository.dart';
import 'package:orchard_atlas/data/workspace_preferences.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/workspaces.dart';
import 'package:orchard_atlas/ui/foraging_screen.dart';
import 'package:orchard_atlas/ui/map_screen.dart';
import 'package:orchard_atlas/ui/orchard_map.dart';
import 'package:orchard_atlas/ui/orchard_theme.dart';
import 'package:orchard_atlas/ui/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mode preference is per account, survives restart and defaults older installations to orchard', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = DeviceWorkspacePreferences(prefs);
    expect(await storage.loadMode('alice'), WorkspaceMode.orchard);
    final controller = WorkspaceModeController(storage, 'alice');
    await controller.select(WorkspaceMode.foraging);
    controller.dispose();
    expect(
      await DeviceWorkspacePreferences(prefs).loadMode('alice'),
      WorkspaceMode.foraging,
    );
    expect(await storage.loadMode('bob'), WorkspaceMode.orchard);
    await storage.saveMode('alice', WorkspaceMode.orchard);
    expect(await storage.loadMode('alice'), WorkspaceMode.orchard);
  });

  Future<(LocalTrialRepository, DeviceWorkspacePreferences)>
  repository() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTrialRepository.open(prefs);
    final taxon = starterTaxonomy.taxa
        .where((t) => t.rank == TaxonRank.species)
        .first
        .id;
    repo.savePlant(
      ManagedPlant(
        id: 'plant',
        propertyId: repo.place.id,
        name: 'Orchard tree',
        taxonId: taxon,
        location: Coordinates(51, 1),
        createdAt: DateTime(2026),
      ),
    );
    final r = ResourceRecord(
      id: 'resource',
      orchard: repo.place.id,
      name: 'Wild pear',
      taxonId: taxon,
      location: Coordinates(52, 2),
      createdAt: DateTime(2026),
    );
    await repo.putRecord(repo.place.id, RecordKind.foraging, r.id, r.toMap());
    return (repo, DeviceWorkspacePreferences(prefs));
  }

  ProviderContainer container(
    LocalTrialRepository repo,
    DeviceWorkspacePreferences prefs,
  ) => ProviderContainer(
    overrides: [
      orchardRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
      workspacePreferencesProvider.overrideWithValue(prefs),
      mapViewRepositoryProvider.overrideWithValue(
        DeviceMapViewRepository(repo.preferences),
      ),
      trialModeProvider.overrideWithValue(true),
      mapsConfiguredProvider.overrideWithValue(false),
    ],
  );
  testWidgets(
    'switcher opens a separate foraging map and list, then orchard selection restores only its plants',
    (tester) async {
      final (repo, prefs) = await repository();
      final north = await repo.createPlace(
        LocalTrialRepository.userId,
        'North orchard',
      );
      final c = container(repo, prefs);
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const OrchardHome())],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        c.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: orchardTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<OrchardMap>(find.byType(OrchardMap)).plants.single.id,
        'plant',
      );
      await tester.tap(find.byTooltip('Switch mode or orchard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foraging'));
      await tester.pumpAndSettle();
      expect(find.byType(ForagingScreen), findsOneWidget);
      expect(
        tester.widget<OrchardMap>(find.byType(OrchardMap)).plants.single.id,
        'resource',
      );
      expect(find.text('Add resource'), findsOneWidget);
      expect(find.text('Add Plant'), findsNothing);
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('Wild pear'), findsOneWidget);
      expect(find.text('Orchard tree'), findsNothing);
      await tester.tap(find.byTooltip('Switch mode or orchard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('North orchard'));
      await tester.pumpAndSettle();
      expect(find.byType(MapScreen), findsOneWidget);
      expect(c.read(placeProvider).value!.id, north.id);
      expect(
        tester.widget<OrchardMap>(find.byType(OrchardMap)).plants,
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => prefs.loadMode(LocalTrialRepository.userId),
        ),
        WorkspaceMode.orchard,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a remembered foraging mode starts directly with its own resources and no orchard controls',
    (tester) async {
      final (repo, prefs) = await repository();
      await prefs.saveMode(LocalTrialRepository.userId, WorkspaceMode.foraging);
      final c = container(repo, prefs);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: orchardTheme(), home: const OrchardHome()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForagingScreen), findsOneWidget);
      expect(find.byType(MapScreen), findsNothing);
      expect(
        tester.widget<OrchardMap>(find.byType(OrchardMap)).plants.single.name,
        'Wild pear',
      );
      expect(find.text('Add row'), findsNothing);
      expect(find.text('Add area'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'forms remain usable with large text and settings no longer hides the foraging entry point',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: orchardTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: OrchardForm(
                title: 'Plant details',
                subtitle: 'Choose your plant and its location.',
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Plant name'),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: const [
                      DropdownMenuItem(value: 'fruit', child: Text('Fruit')),
                    ],
                    onChanged: (_) {},
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Save plant'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save plant'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(theme: orchardTheme(), home: const SettingsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Foraging resources'), findsNothing);
      expect(find.text('Orchard sharing'), findsOneWidget);
    },
  );
}
