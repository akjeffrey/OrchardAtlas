import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/domain/map_icons.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/edit_plant_screen.dart';
import 'package:orchard_atlas/ui/icon_library_screen.dart';
import 'package:orchard_atlas/ui/icon_picker.dart';

import 'support/icon_fixture.dart';

void main() {
  Future<LocalTrialRepository> repository() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  Finder dropdown(String label) => find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  testWidgets(
    'Edit Plant creates a complete custom hierarchy while preserving the draft and history',
    (tester) async {
      final repo = await repository();
      final plant = OrchardCommands(repo, starterTaxonomy).addPlant(
        place: repo.place,
        name: 'Old plant',
        taxonId: starterTaxonomy.taxa[2].id,
        location: Coordinates(51, 1),
        plantingDate: DateTime(2020),
        authorId: LocalTrialRepository.userId,
      );
      final eventId = repo.events.single.id;
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'art', name: 'Orchard art', png: iconPng()),
      );
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(path: '/edit', builder: (_, _) => EditPlantScreen(plant.id)),
          GoRoute(
            path: '/plants/:id',
            builder: (_, _) => const Scaffold(body: Text('Saved changes')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Plant name'),
        'Unsaved draft',
      );
      Future<void> add(String level) async {
        await tester.ensureVisible(dropdown(level));
        await tester.tap(dropdown(level));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+ Add new option…').last);
        await tester.pumpAndSettle();
        expect(find.text('Add $level'), findsOneWidget);
      }

      await add('Variety');
      await tester.enterText(
        find.widgetWithText(TextField, 'Option name'),
        'Cancelled option',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.taxa, isEmpty);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Plant name'))
            .controller!
            .text,
        'Unsaved draft',
      );
      for (final level in ['Group', 'Type', 'Variety']) {
        await add(level);
        if (level == 'Group') {
          await tester.tap(find.text('Add option'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Option name'), findsWidgets);
          await tester.enterText(
            find.widgetWithText(TextField, 'Option name'),
            'Fruit trees',
          );
          await tester.tap(find.text('Add option'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('This option already exists'),
            findsOneWidget,
          );
          await tester.tap(dropdown('Map icon'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Orchard art').last);
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Option name'),
          'New $level',
        );
        await tester.tap(find.text('Add option'));
        await tester.pumpAndSettle();
        expect(find.text('New $level'), findsOneWidget);
        expect(repo.plants.single.taxonId, plant.taxonId);
        expect(repo.plants.single.name, 'Old plant');
      }
      final taxonomy = orchardTaxonomy(repo.taxa);
      final variety = repo.taxa.singleWhere((t) => t.name == 'New Variety');
      expect(taxonomy.ancestry(variety.id).map((t) => t.name), [
        'New Group',
        'New Type',
        'New Variety',
      ]);
      expect(taxonomy.iconFor(variety.id).customIconId, 'art');
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Saved changes'), findsOneWidget);
      expect(repo.plants.single.id, plant.id);
      expect(repo.plants.single.name, 'Unsaved draft');
      expect(repo.plants.single.taxonId, variety.id);
      expect(repo.plants.single.location.latitude, 51);
      expect(repo.events.single.id, eventId);
      final archive = await TrialBackupStore(repo.preferences, repo).export();
      await TrialBackupStore(repo.preferences, repo).restore(archive);
      final restarted = LocalTrialRepository.open(repo.preferences);
      expect(restarted.plants.single.taxonId, variety.id);
      expect(
        orchardTaxonomy(restarted.taxa).byId(variety.id).name,
        'New Variety',
      );
    },
  );

  testWidgets(
    'custom icon rename validates, cancels, updates choices and persists',
    (tester) async {
      final repo = await repository();
      repo.saveIcon(
        repo.place.id,
        MapIcon(id: 'art', name: 'Original artwork', png: iconPng()),
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
      await tester.tap(find.byTooltip('Rename Original artwork'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Icon name');
      expect(
        tester.widget<TextFormField>(field).initialValue,
        'Original artwork',
      );
      await tester.enterText(field, 'Cancelled name');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.icons.single.name, 'Original artwork');
      await tester.tap(find.byTooltip('Rename Original artwork'));
      await tester.pumpAndSettle();
      await tester.enterText(field, '   ');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter an icon name'), findsOneWidget);
      await tester.enterText(field, '  Renamed artwork  ');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed artwork'), findsOneWidget);
      expect(repo.icons.single.id, 'art');
      expect(repo.icons.single.png, iconPng());
      await repo.flushForBackup();
      expect(
        LocalTrialRepository.open(repo.preferences).icons.single.name,
        'Renamed artwork',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orchardRepositoryProvider.overrideWithValue(repo),
            placeProvider.overrideWith((ref) async => repo.place),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MapIconPicker(customIconId: 'art', onChanged: (_, _) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Renamed artwork'), findsOneWidget);
    },
  );
}
