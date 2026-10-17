import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'activity_screen.dart';
import 'backup_screen.dart';
import 'add_plant_screen.dart';
import 'map_screen.dart';
import 'plant_detail_screen.dart';
import 'sign_in_screen.dart';
import 'edit_plant_screen.dart';
import 'tasks_screen.dart';
import 'sections_screen.dart';
import 'crops_screen.dart';
import 'archived_plants.dart';
import 'classification_screen.dart';
import '../domain/landscape.dart';

final dismissedFailureProvider = StateProvider<String?>((ref) => null);

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(userProvider);
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (user.isLoading) return null;
      final authenticated = user.valueOrNull != null;
      if (!authenticated && state.matchedLocation != '/sign-in') {
        return '/sign-in';
      }
      if (authenticated && state.matchedLocation == '/sign-in') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
      GoRoute(
        path: '/archived',
        builder: (_, _) => const ArchivedPlantsScreen(),
      ),
      GoRoute(
        path: '/classifications',
        builder: (_, _) => const ClassificationScreen(),
      ),
      GoRoute(
        path: '/layout',
        builder: (_, state) => SectionsScreen(
          initialCamera: state.extra is CameraPosition
              ? state.extra as CameraPosition
              : null,
        ),
      ),
      GoRoute(
        path: '/sections/new',
        builder: (_, state) => SectionFormScreen(
          parentId: state.extra is String ? state.extra as String : null,
          initialCamera: state.extra is CameraPosition
              ? state.extra as CameraPosition
              : null,
        ),
      ),
      GoRoute(
        path: '/sections/:id',
        builder: (_, state) => SectionDetailScreen(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sections/:id/edit',
        builder: (_, state) =>
            SectionFormScreen(sectionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/crops/new',
        builder: (_, state) => CropFormScreen(
          section: state.extra is OrchardSection
              ? state.extra as OrchardSection
              : null,
          source: state.extra is CropPlanting
              ? state.extra as CropPlanting
              : null,
        ),
      ),
      GoRoute(
        path: '/crops/:id',
        builder: (_, state) => CropDetailScreen(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/crops/:id/harvest',
        builder: (_, state) => CropHarvestScreen(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/task-groups/:id',
        builder: (_, state) => TaskGroupScreen(state.pathParameters['id']!),
      ),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/',
        builder: (_, state) => OrchardHome(
          focus: state.extra is Coordinates ? state.extra as Coordinates : null,
        ),
      ),
      GoRoute(
        path: '/plants/new',
        builder: (_, state) => AddPlantScreen(
          sectionId: state.extra is OrchardSection
              ? (state.extra as OrchardSection).id
              : null,
          template: state.extra is PlantTemplate
              ? state.extra as PlantTemplate
              : null,
          location: state.extra is Coordinates
              ? state.extra as Coordinates
              : null,
        ),
      ),
      GoRoute(
        path: '/plants/:id',
        builder: (_, state) => PlantDetailScreen(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plants/:id/edit',
        builder: (_, state) => EditPlantScreen(state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plants/:id/tasks',
        builder: (_, state) => TasksScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tasks/new',
        builder: (_, state) => TaskFormScreen(
          itemId: state.extra is String ? state.extra as String : null,
          sectionId: state.extra is TaskTarget
              ? (state.extra as TaskTarget).sectionId
              : null,
          cropId: state.extra is TaskTarget
              ? (state.extra as TaskTarget).cropId
              : null,
        ),
      ),
      GoRoute(
        path: '/plants/:id/activity',
        builder: (_, state) => ActivityScreen(
          state.pathParameters['id']!,
          event: state.extra is PlantEvent ? state.extra as PlantEvent : null,
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class OrchardAtlasApp extends ConsumerWidget {
  const OrchardAtlasApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(sessionLockedProvider);
    final trial = ref.watch(trialModeProvider);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315e35)),
      useMaterial3: true,
    );
    if (locked) {
      return MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Session closed. Restart OrchardAtlas before signing in again. If cache clearing failed, the previous account remains signed in; retry sign-out after restart.',
              ),
            ),
          ),
        ),
      );
    }
    if (ref.watch(userProvider).isLoading) {
      return MaterialApp(
        theme: theme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (trial) ref.watch(backupServiceProvider);
    ref.watch(taskMaterializerProvider);
    final failure = ref.watch(failuresProvider).valueOrNull;
    final dismissedFailure = ref.watch(dismissedFailureProvider);
    return MaterialApp.router(
      title: 'OrchardAtlas',
      theme: theme,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Column(
        children: [
          if (trial)
            SafeArea(
              bottom: false,
              child: Material(
                color: theme.colorScheme.secondaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'PHONE TRIAL · Local data · Drive backup in Orchard options',
                  ),
                ),
              ),
            ),
          if (failure != null && dismissedFailure != failure.recordId)
            SafeArea(
              bottom: false,
              child: Material(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${failure.message}\nRecord: ${failure.recordId}',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss sync warning',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            ref.read(dismissedFailureProvider.notifier).state =
                                failure.recordId,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
