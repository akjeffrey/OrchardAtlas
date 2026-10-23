import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plant_listing.dart';
import 'providers.dart';

final plantEntriesProvider = Provider<AsyncValue<List<PlantEntry>>>((ref) {
  final plants = ref.watch(plantsProvider),
      crops = ref.watch(cropsProvider),
      sections = ref.watch(sectionsProvider);
  for (final value in [plants, crops, sections]) {
    if (value.hasError) {
      return AsyncError(value.error!, value.stackTrace ?? StackTrace.current);
    }
    if (value.isLoading || value.valueOrNull == null) {
      return const AsyncLoading();
    }
  }
  try {
    return AsyncData(
      plantEntries(
        plants.value!.value,
        crops.value!.value,
        sections.value!.value,
      ),
    );
  } catch (_) {
    return AsyncError(
      StateError(
        'Some planting locations are unavailable. Reconnect to load their Areas/Rows.',
      ),
      StackTrace.current,
    );
  }
});
