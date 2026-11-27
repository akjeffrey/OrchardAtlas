import 'dart:convert';
import 'dart:typed_data';
import '../domain/extensions.dart';
import 'extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/seed_trays.dart';
import 'providers.dart';

final seedTrayRepositoryProvider = Provider<SeedTrayRepository>(
  (ref) => ref.watch(orchardRepositoryProvider) as SeedTrayRepository,
);
final seedTraysProvider = StreamProvider.autoDispose<List<SeedTray>>((
  ref,
) async* {
  final repo = ref.watch(seedTrayRepositoryProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repo.watchSeedTrays(place.id);
});
final trayCellsProvider = StreamProvider.autoDispose
    .family<Map<TrayPosition, TrayAssignment>, String>((ref, id) async* {
      final repo = ref.watch(seedTrayRepositoryProvider);
      final place = await ref.watch(placeProvider.future);
      yield* repo.watchTrayCells(place.id, id);
    });

/// Shared thumbnail bytes per photo ID, retained by the photo repository offline.
final seedPacketThumbnailProvider = Provider.autoDispose.family<Uint8List?,String>((ref,id) {
  final records=ref.watch(recordsProvider(RecordKind.photo)).asData?.value;
  final value=records?.where((p)=>p['id']==id).firstOrNull?['thumbnail'];
  if(value is! String || value.length>43692) {return null;}
  try {
    final bytes=base64Decode(value);
    return bytes.isEmpty || bytes.length>32*1024 ? null : bytes;
  }on FormatException {return null;}
});
