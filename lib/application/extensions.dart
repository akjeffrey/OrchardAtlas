import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/extensions.dart';
import '../domain/find_sharing.dart';
import '../data/find_sharing.dart';
import '../domain/work.dart';
import '../domain/models.dart';
import '../data/extension_devices.dart';
import 'providers.dart';

final orchardRecordsProvider = Provider<OrchardRecords>(
  (ref) => ref.watch(orchardRepositoryProvider) as OrchardRecords,
);
final recordsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, RecordKind>((ref, kind) async* {
      final repo = ref.watch(orchardRecordsProvider);
      final orchard = await ref.watch(placeProvider.future);
      yield* repo.watchRecords(orchard.id, kind);
    });
final resourcesProvider = Provider<AsyncValue<List<ResourceRecord>>>((ref) {
  final orchard = ref.watch(placeProvider).asData?.value;
  return ref
      .watch(recordsProvider(RecordKind.foraging))
      .whenData(
        (r) => orchard == null
            ? []
            : [
                for (final d in r.where((d) => d['parentId'] == null))
                  ResourceRecord.read(orchard.id, d),
              ],
      );
});
final cameraProvider = Provider<CameraRepository>((ref) => DeviceCamera());
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => DeviceReminders(),
);
final sharingProvider = Provider<SharingRepository?>((ref) => null);
final accountEmailProvider = Provider<String?>(
  (ref) => ref.watch(userProvider).valueOrNull?.email?.toLowerCase(),
);
final incomingInvitationsProvider = StreamProvider<List<OrchardInvitation>>((
  ref,
) {
  final repo = ref.watch(sharingProvider),
      email = ref.watch(accountEmailProvider);
  return repo == null || email == null
      ? Stream.value([])
      : repo.invitations(email);
});
final orchardMembersProvider = StreamProvider<List<Permission>>((ref) async* {
  final repo = ref.watch(sharingProvider);
  final place = await ref.watch(placeProvider.future);
  yield* repo?.members(place.id) ?? Stream.value([]);
});
final canEditOrchardProvider = Provider<bool>((ref) {
  final p = ref.watch(placeProvider).asData?.value,
      u = ref.watch(userProvider).valueOrNull;
  return p != null &&
      u != null &&
      (p.ownerId == u.id ||
          (ref.watch(orchardMembersProvider).valueOrNull ?? []).any(
            (m) => m.userId == u.id && m.role == PermissionRole.editor,
          ));
});

/// One serialized worker; source bytes stay durable until object upload succeeds.
final photoWorkerProvider = Provider<void>((ref) {
  if (ref.watch(trialModeProvider)) return;
  final photos = ref.watch(recordsProvider(RecordKind.photo)).asData?.value;
  final place = ref.watch(placeProvider).asData?.value;
  final repo = ref.watch(orchardRecordsProvider);

  final permitted = ref.watch(canEditOrchardProvider);
  if (photos == null ||
      place == null ||
      !permitted ||
      !photos.any((p) => p['state'] == 'pending')) {
    return;
  }
  final uploader = ref.watch(photoRepositoryProvider);
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final worker = ref.watch(photoQueueProvider);
  scheduleMicrotask(
    () => worker.drain(
      place.id,
      photos,
      repo,
      (p, bytes) => uploader.upload(p, bytes, 'image/jpeg'),
    ),
  );
});
final photoQueueProvider = Provider<PhotoQueue>((ref) => PhotoQueue());

class PhotoQueue {
  bool _running = false;
  Future<void> drain(
    String orchard,
    List<Map<String, dynamic>> records,
    OrchardRecords repo,
    Future<void> Function(Photo, Uint8List) upload,
  ) async {
    if (_running) return;
    _running = true;
    try {
      for (final d in records.where((r) => r['state'] == 'pending')) {
        try {
          final p = Photo(
            id: d['id'] as String,
            propertyId: orchard,
            itemId: d['itemId'] as String,
            authorId: d['authorId'] as String,
            storagePath: d['storagePath'] as String,
          );
          await upload(
            p,
            base64Decode(d['image'] as String),
          ).timeout(const Duration(seconds: 45));
          final latest = await repo
              .watchRecords(orchard, RecordKind.photo)
              .first;
          if (!latest.any((r) => r['id'] == p.id)) continue;
          await repo.putRecord(orchard, RecordKind.photo, p.id, {
            ...d,
            'state': 'uploaded',
            'image': null,
            'error': null,
          });
        } catch (e) {
          final latest = await repo
              .watchRecords(orchard, RecordKind.photo)
              .first;
          if (!latest.any((r) => r['id'] == d['id'])) continue;
          // Keep source bytes and pending state for the next startup/retry.
          await repo.putRecord(orchard, RecordKind.photo, d['id'] as String, {
            ...d,
            'error': 'Upload pending; check connection and orchard access.',
          });
        }
      }
    } finally {
      _running = false;
    }
  }
}

Future<void> addPhoto(
  WidgetRef ref,
  String itemId, {
  required bool camera,
}) async {
  final orchard = await ref.read(placeProvider.future);
  final user = ref.read(userProvider).valueOrNull;
  if (user == null) throw StateError('Please sign in');
  final captured = await ref.read(cameraProvider).capture(camera: camera);
  if (captured == null) return;
  if (captured.image.length > 512 * 1024 ||
      captured.thumbnail.length > 32 * 1024) {
    throw StateError('Image exceeds supported size');
  }
  if ((await ref.read(placeProvider.future)).id != orchard.id) {
    throw StateError('Orchard changed');
  }
  final id = const Uuid().v4();
  await ref.read(orchardRecordsProvider).putRecord(
    orchard.id,
    RecordKind.photo,
    id,
    {
      'itemId': itemId,
      'authorId': user.id,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'storagePath': 'properties/${orchard.id}/items/$itemId/photos/$id.jpg',
      'image': base64Encode(captured.image),
      'thumbnail': base64Encode(captured.thumbnail),
      'state': ref.read(trialModeProvider) ? 'local' : 'pending',
      'error': null,
    },
  );
}

List<Map<String, dynamic>> dueNotifications(
  List<OrchardTask> tasks,
  List<Map<String, dynamic>> reminders,
  DateTime now,
) {
  final result = <Map<String, dynamic>>[];
  for (final r in reminders) {
    final matches = tasks
        .where(
          (t) =>
              (t.id == r['id'] || t.planId == r['id']) &&
              t.status == TaskStatus.open &&
              t.dueDate != null,
        )
        .toList();
    final days = r['days'] as int;
    if (days < 0 || days > 365) continue;
    final dates = <String, List<OrchardTask>>{};
    for (final t in matches) {
      dates.putIfAbsent(t.dueDate!, () => []).add(t);
    }
    for (final entry in dates.entries) {
      final due = parseCalendarDate(entry.key);
      final day = due.subtract(Duration(days: days));
      final time = DateTime(day.year, day.month, day.day, 9);
      // Past reminders are not delivered again on every restart.
      if (!time.isAfter(now)) continue;
      result.add({
        'id': '${r['id']}/${entry.key}',
        'title': entry.value.first.title,
        'body': '${entry.value.length} open target(s) · due ${entry.key}',
        'time': time.millisecondsSinceEpoch,
      });
    }
  }
  result.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
  return result.take(60).toList();
}

final reminderWorkerProvider = Provider<void>((ref) {
  final tasks = ref.watch(tasksProvider).asData?.value.value;
  final records = ref.watch(recordsProvider(RecordKind.reminder)).asData?.value;
  final scheduler = ref.watch(reminderSchedulerProvider);
  if (tasks == null || records == null) return;
  final now = ref.watch(minuteClockProvider);
  final plans = ref.watch(taskPlansProvider).asData?.value;
  final plants = ref.watch(plantsProvider).asData?.value.value;
  final crops = ref.watch(cropsProvider).asData?.value.value;
  final sections = ref.watch(sectionsProvider).asData?.value.value;
  final predictions =
      plans == null || plants == null || crops == null || sections == null
      ? <OrchardTask>[]
      : expandPlans(
          plans: plans,
          existing: tasks,
          plants: plants,
          sections: sections,
          crops: crops,
          taxonomy: ref.watch(taxonomyProvider),
          now: now.add(const Duration(days: 30)),
        );
  final orchard = ref.watch(placeProvider).asData?.value;
  if (orchard == null) return;
  scheduleMicrotask(() async {
    try {
      await scheduler.replace(
        orchard.id,
        dueNotifications([...tasks, ...predictions], records, now),
      );
    } on MissingPluginException {
      /* Simulator/unsupported platform. */
    } on PlatformException {
      /* User may block notifications; settings explains this. */
    }
  });
});

final publicResourcesProvider =
    StreamProvider.autoDispose<List<ResourceRecord>>(
      (ref) =>
          ref.watch(sharingProvider)?.publicResources() ?? Stream.value([]),
    );

final viewOnlyOrchardProvider = Provider<bool>(
  (ref) =>
      ref.watch(placeProvider).hasValue &&
      ref.watch(userProvider).valueOrNull != null &&
      !ref.watch(canEditOrchardProvider),
);

final findSharingProvider = Provider<FindSharingRepository>(
  (ref) => DeviceFindSharing(),
);
