import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
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
  final place = await ref.watch(placeProvider.future);
  yield* directory.watchPlaces(place.ownerId);
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
  if (selected != null && selected.ownerId == user.id) return selected;
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
    String rootstock = '',
    String nursery = '',
    String notes = '',
    double? accuracyMeters,
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
      plantedOn: plantingDate == null ? null : calendarDate(plantingDate),
      rootstock: rootstock,
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
