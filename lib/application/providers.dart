import '../domain/filters.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_trial_repository.dart';
import '../data/trial_backup_store.dart';
import '../data/backup_documents.dart';
import 'backup_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'dart:async';

import '../domain/work.dart';

import '../domain/models.dart';
import '../domain/map_icons.dart';
import '../data/icon_importer.dart';
import '../domain/landscape.dart';
import '../domain/repositories.dart';
import '../domain/taxonomy.dart';
import '../domain/map_search.dart';
import '../domain/orchards.dart';

final orchardDirectoryProvider = Provider<OrchardDirectoryRepository>(
  (ref) => ref.watch(orchardRepositoryProvider) as OrchardDirectoryRepository,
);
final selectedOrchardProvider = StateProvider<Place?>((ref) => null);
final orchardsProvider = StreamProvider<List<Place>>((ref) async* {
  final directory = ref.watch(orchardDirectoryProvider);
  await ref.watch(placeProvider.future);
  yield* directory.watchPlaces(ref.read(userProvider).value!.id);
});
final mapViewRepositoryProvider = Provider<MapViewRepository>(
  (ref) => throw UnimplementedError(),
);
final defaultMapViewProvider = FutureProvider<OrchardMapView?>((ref) async {
  final repository = ref.watch(mapViewRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  return repository.load(place.ownerId, place.id);
});

final addressSearchRepositoryProvider = Provider<AddressSearchRepository>(
  (ref) => throw UnimplementedError(),
);
// Startup overrides this using native configuration, for trial and connected mode.
final mapsConfiguredProvider = Provider<bool>(
  (ref) => !ref.watch(trialModeProvider),
);

final orchardRepositoryProvider = Provider<OrchardRepository>(
  (ref) => throw UnimplementedError(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError(),
);
final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => throw UnimplementedError(),
);
final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) => throw UnimplementedError(),
);
final trialModeProvider = Provider<bool>((ref) => false);
final customTaxaProvider = StreamProvider<List<Taxon>>((ref) async* {
  final repository = ref.watch(orchardRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repository.watchTaxa(place.id);
});
final iconImporterProvider = Provider<IconImporter>(
  (ref) => DeviceIconImporter(),
);
final mapIconsProvider = StreamProvider.autoDispose<List<MapIcon>>((
  ref,
) async* {
  final repository = ref.watch(orchardRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repository.watchIcons(place.id);
});

final submittedTaxaProvider = StateProvider<Map<String, Taxon>>((ref) => {});
final taxonomyProvider = Provider<Taxonomy>(
  (ref) => Taxonomy(
    {
      for (final t in starterTaxonomy.taxa) t.id: t,
      ...ref.watch(submittedTaxaProvider),
      for (final t in ref.watch(customTaxaProvider).asData?.value ?? <Taxon>[])
        t.id: t,
    }.values.toList(),
  ),
);
final userProvider = StreamProvider(
  (ref) => ref.watch(authRepositoryProvider).userChanges,
);
final sessionLockedProvider = StateProvider<bool>((ref) => false);
final placeProvider = FutureProvider.autoDispose<Place>((ref) async {
  final user = ref.watch(userProvider).valueOrNull;
  if (user == null) throw StateError('Please sign in');
  final selected = ref.watch(selectedOrchardProvider);
  if (selected != null) return selected;
  return ref.watch(orchardRepositoryProvider).openDefaultPlace(user.id);
});
final plantsProvider =
    StreamProvider.autoDispose<RepositorySnapshot<List<ManagedPlant>>>((
      ref,
    ) async* {
      final repository = ref.watch(orchardRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repository.watchPlants(place.id);
    });
final eventsProvider = StreamProvider.autoDispose
    .family<RepositorySnapshot<List<PlantEvent>>, String>((ref, id) async* {
      final repository = ref.watch(orchardRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repository.watchEvents(place.id, id);
    });
final tasksProvider =
    StreamProvider.autoDispose<RepositorySnapshot<List<OrchardTask>>>((
      ref,
    ) async* {
      final repository = ref.watch(orchardRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repository.watchTasks(place.id);
    });
final failuresProvider = StreamProvider(
  (ref) => ref.watch(orchardRepositoryProvider).writeFailures,
);
final commandsProvider = Provider(
  (ref) => OrchardCommands(
    ref.watch(orchardRepositoryProvider),
    ref.watch(taxonomyProvider),
  ),
);

class OrchardCommands {
  OrchardCommands(this.repository, this.taxonomy, {String Function()? newId})
    : newId = newId ?? const Uuid().v4;
  final OrchardRepository repository;
  final Taxonomy taxonomy;
  final String Function() newId;
  ManagedPlant addPlant({
    required Place place,
    required String name,
    required String taxonId,
    required Coordinates location,
    DateTime? plantingDate,
    String? authorId,
    String? sectionId,
    PlantLifeCycle lifeCycle = PlantLifeCycle.perennial,
    String? season,
    String rootstock = '',
    String nursery = '',
    String notes = '',
    double? accuracyMeters,
    double? rowOrder,
  }) {
    if (!taxonomy.isPlantIdentity(taxonId)) {
      throw ArgumentError('Select a species or cultivar');
    }
    final plant = ManagedPlant(
      id: newId(),
      propertyId: place.id,
      name: name.trim().isEmpty ? taxonomy.byId(taxonId).name : name,
      taxonId: taxonId,
      location: location,
      createdAt: DateTime.now().toUtc(),
      sectionId: sectionId,
      rowOrder: rowOrder,
      plantedOn: plantingDate == null ? null : calendarDate(plantingDate),
      rootstock: rootstock,
      lifeCycle: lifeCycle,
      season: season,
      nursery: nursery,
      notes: notes,
      accuracyMeters: accuracyMeters,
    );
    if (plantingDate != null && authorId == null) {
      throw ArgumentError('Planting author required');
    }
    final plantingEvent = plantingDate == null
        ? null
        : PlantEvent(
            id: newId(),
            propertyId: place.id,
            itemId: plant.id,
            authorId: authorId!,
            type: ActivityType.planting,
            occurredAt: plantingDate.toUtc(),
            activityDate: calendarDate(plantingDate),
            recordedAt: DateTime.now().toUtc(),
          );
    repository.savePlant(plant, plantingEvent: plantingEvent);
    return plant;
  }

  void changeTaskStatus(OrchardTask old, TaskStatus status, String authorId) {
    if (old.status == status) return;
    final task = old.withStatus(status);
    PlantEvent? event;
    if (status == TaskStatus.completed &&
        task.eventType != null &&
        task.itemId != null) {
      final now = DateTime.now();
      event = PlantEvent(
        id: linkedEventId(task.id),
        propertyId: task.propertyId,
        itemId: task.itemId!,
        authorId: authorId,
        type: task.eventType!,
        occurredAt: now.toUtc(),
        activityDate: calendarDate(now),
        recordedAt: now.toUtc(),
        notes: task.notes,
        harvest: task.eventType == ActivityType.harvest
            ? task.eventHarvest
            : null,
        taskId: task.id,
      );
    }
    if (task.eventType == null) {
      repository.saveTask(task);
    } else {
      repository.saveTaskWithEvent(task, event);
    }
  }

  void record({
    required Place place,
    required String itemId,
    required String authorId,
    required ActivityType type,
    required DateTime date,
    required String notes,
    Harvest? harvest,
  }) {
    repository.appendEvent(
      PlantEvent(
        id: newId(),
        propertyId: place.id,
        itemId: itemId,
        authorId: authorId,
        type: type,
        occurredAt: date.toUtc(),
        activityDate: calendarDate(date),
        recordedAt: DateTime.now().toUtc(),
        notes: notes.trim(),
        harvest: harvest,
      ),
    );
  }
}

final sectionsProvider =
    StreamProvider<RepositorySnapshot<List<OrchardSection>>>((ref) async* {
      final repo = ref.watch(orchardRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repo.watchSections(place.id);
    });
final cropsProvider = StreamProvider<RepositorySnapshot<List<CropPlanting>>>((
  ref,
) async* {
  final repo = ref.watch(orchardRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repo.watchCrops(place.id);
});
final cropHarvestsProvider =
    StreamProvider<RepositorySnapshot<List<CropHarvest>>>((ref) async* {
      final repo = ref.watch(orchardRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repo.watchCropHarvests(place.id);
    });

final taskPlansProvider = StreamProvider<List<TaskPlan>>((ref) async* {
  final repository = ref.watch(orchardRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repository.watchTaskPlans(place.id);
});
final minuteClockProvider = Provider<DateTime>((ref) {
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return DateTime.now();
});
final taskMaterializerProvider = Provider<int>((ref) {
  final plans = ref.watch(taskPlansProvider).asData?.value;
  final tasks = ref.watch(tasksProvider).asData?.value.value;
  final plants = ref.watch(plantsProvider).asData?.value.value;
  final sections = ref.watch(sectionsProvider).asData?.value.value;
  final crops = ref.watch(cropsProvider).asData?.value.value;
  final taxonomy = ref.watch(taxonomyProvider),
      now = ref.watch(minuteClockProvider);
  final repository = ref.watch(orchardRepositoryProvider);
  if (plans == null ||
      tasks == null ||
      plants == null ||
      sections == null ||
      crops == null) {
    return 0;
  }
  final pending = expandPlans(
    plans: plans,
    existing: tasks,
    plants: plants,
    sections: sections,
    crops: crops,
    taxonomy: taxonomy,
    now: now,
  );
  if (pending.isNotEmpty) {
    scheduleMicrotask(() {
      for (final task in pending) {
        repository.saveTask(task);
      }
    });
  }
  return pending.length;
});
final allEventsProvider = Provider<AsyncValue<List<PlantEvent>>>((ref) {
  final plants = ref.watch(plantsProvider);
  if (plants.hasError) return AsyncError(plants.error!, StackTrace.current);
  if (plants.asData == null) return const AsyncLoading();
  final result = <PlantEvent>[];
  for (final plant in plants.value!.value) {
    final events = ref.watch(eventsProvider(plant.id));
    if (events.hasError) return AsyncError(events.error!, StackTrace.current);
    if (events.asData == null) return const AsyncLoading();
    result.addAll(events.value!.value);
  }
  result.sort((a, b) => b.activityDate.compareTo(a.activityDate));
  return AsyncData(result);
});

final backupPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final plantFilterProvider = StateProvider<PlantFilter>(
  (ref) => const PlantFilter(),
);
final backupServiceProvider = ChangeNotifierProvider<BackupService>(
  (ref) => BackupService(
    TrialBackupStore(
      ref.watch(backupPreferencesProvider),
      ref.watch(orchardRepositoryProvider) as LocalTrialRepository,
    ),
    AndroidBackupDocuments(),
    onRestored: () {
      ref.read(selectedOrchardProvider.notifier).state = null;
      ref.read(submittedTaxaProvider.notifier).state = {};
      ref.read(plantFilterProvider.notifier).state = const PlantFilter();
      ref.invalidate(orchardRepositoryProvider);
    },
  ),
);
