import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/seed_trays.dart';
import 'providers.dart';

final seedTrayRepositoryProvider=Provider<SeedTrayRepository>((ref)=>ref.watch(orchardRepositoryProvider) as SeedTrayRepository);
final seedTraysProvider=StreamProvider.autoDispose<List<SeedTray>>((ref)async*{
  final repo=ref.watch(seedTrayRepositoryProvider);
  final place=await ref.watch(placeProvider.future);
  yield* repo.watchSeedTrays(place.id);
});
final trayCellsProvider=StreamProvider.autoDispose.family<Map<TrayPosition,TrayAssignment>,String>((ref,id)async*{
  final repo=ref.watch(seedTrayRepositoryProvider);
  final place=await ref.watch(placeProvider.future);
  yield* repo.watchTrayCells(place.id,id);
});
