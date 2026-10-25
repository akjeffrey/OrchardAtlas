import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/extensions.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/data/trial_backup_store.dart';
import 'package:orchard_atlas/data/event_revision_codec.dart';
import 'package:orchard_atlas/data/work_mapping.dart';
import 'package:orchard_atlas/domain/backup.dart';
import 'package:orchard_atlas/domain/extensions.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/domain/task_edits.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/domain/yield_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 10, 25);
  final taxon = starterTaxonomy.taxa
      .where((t) => t.rank == TaxonRank.species)
      .first
      .id;
  ManagedPlant plant(String orchard) => ManagedPlant(
    id: 'plant',
    propertyId: orchard,
    name: 'Pear',
    taxonId: taxon,
    location: Coordinates(1, 2),
    createdAt: date,
  );
  PlantEvent event(String orchard, {double quantity = 2}) => PlantEvent(
    id: 'event',
    propertyId: orchard,
    itemId: 'plant',
    authorId: LocalTrialRepository.userId,
    type: ActivityType.harvest,
    occurredAt: date,
    activityDate: '2026-10-25',
    recordedAt: date,
    harvest: Harvest(quantity, HarvestUnit.kg),
  );
  Future<LocalTrialRepository> local() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }

  test(
    'foraging winter season wraps around and validates month boundaries',
    () {
      final r = ResourceRecord(
        id: 'r',
        orchard: 'p',
        name: 'Nuts',
        taxonId: taxon,
        location: Coordinates(1, 2),
        createdAt: date,
        startMonth: 10,
        endMonth: 2,
      );
      expect(
        [r.inSeason(1), r.inSeason(10), r.inSeason(2), r.inSeason(8)],
        [true, true, true, false],
      );
      expect(ResourceRecord.read('p', r.toMap()).location.longitude, 2);
      expect(
        () => ResourceRecord(
          id: 'r',
          orchard: 'p',
          name: 'Nuts',
          taxonId: taxon,
          location: Coordinates(1, 2),
          createdAt: date,
          startMonth: 0,
        ),
        throwsArgumentError,
      );
    },
  );
  test('resources, observations and local photos persist, remain orchard-scoped and restore with Drive backup', () async {
    final repo = await local();
    final r = ResourceRecord(
      id: 'resource',
      orchard: repo.place.id,
      name: 'Nuts',
      taxonId: taxon,
      location: Coordinates(1, 2),
      createdAt: date,
    );
    await repo.putRecord(repo.place.id, RecordKind.foraging, r.id, r.toMap());
    await repo.putRecord(repo.place.id, RecordKind.foraging, 'observation', {
      'parentId': r.id,
      'observation': 'Ripe',
      'date': '2026-10-25',
    });
    await repo.putRecord(repo.place.id, RecordKind.photo, 'photo', {
      'itemId': r.id,
      'image': base64Encode([1, 2, 3]),
      'thumbnail': base64Encode([1]),
      'state': 'local',
    });
    final other = await repo.createPlace(LocalTrialRepository.userId, 'Other');
    expect(
      await repo.watchRecords(other.id, RecordKind.foraging).first,
      isEmpty,
    );
    final contents = await TrialBackupStore(repo.preferences, repo).export();
    final archive = BackupArchive.decode(contents);
    expect(archive.records[LocalTrialRepository.storageKey], contains('Ripe'));
    final restored = LocalTrialRepository.open(
      repo.preferences,
      snapshot: archive.records[LocalTrialRepository.storageKey],
    );
    expect(
      await restored.watchRecords(repo.place.id, RecordKind.foraging).first,
      hasLength(2),
    );
    expect(
      (await restored.watchRecords(repo.place.id, RecordKind.photo).first)
          .single['state'],
      'local',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('activity revisions retain pre-edit and deleted harvest values through restart', () async {
    final repo = await local();
    repo.savePlant(plant(repo.place.id));
    repo.appendEvent(event(repo.place.id));
    repo.updateEvent(event(repo.place.id, quantity: 5));
    repo.deleteEvent(event(repo.place.id, quantity: 5));
    await repo.flushForBackup();
    final restarted = LocalTrialRepository.open(repo.preferences);
    final revisions = await restarted
        .watchRecords(repo.place.id, RecordKind.activityRevision)
        .first;
    expect(revisions, hasLength(2));
    expect(
      revisions.map(
        (r) => EventRevisionCodec.read(repo.place.id, r).harvest!.quantity,
      ),
      containsAll([2, 5]),
    );
    expect(
      await restarted
          .watchEvents(repo.place.id, 'plant')
          .first
          .then((s) => s.value),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('one-off plan edits preserve IDs and completed activity links when due date changes', () {
    final original = TaskPlan(
      id: 'plan',
      propertyId: 'p',
      title: 'Prune',
      createdAt: date,
      target: 'plants',
      dueDate: '2026-10-25',
    );
    final existing = expandPlans(
      plans: [original],
      existing: [],
      plants: [plant('p')],
      sections: [],
      crops: [],
      taxonomy: starterTaxonomy,
      now: date,
    );
    final edited = editPlan(
      original,
      title: 'Prune carefully',
      notes: 'Leave leader',
      dueDate: '2026-11-01',
      eventType: ActivityType.pruning,
    );
    expect(occurrenceDates(edited, date), ['2026-10-25']);
    expect(
      WorkMapping.readPlan('p', 'plan', WorkMapping.plan(edited)).anchorOn,
      '2026-10-25',
    );
    expect(
      expandPlans(
        plans: [edited],
        existing: existing,
        plants: [plant('p')],
        sections: [],
        crops: [],
        taxonomy: starterTaxonomy,
        now: date,
      ),
      isEmpty,
    );
    final completed = existing.single.withStatus(
      TaskStatus.completed,
      now: date,
    );
    expect(
      identical(
        editOpenTask(completed, title: 'Other', notes: 'Changed'),
        completed,
      ),
      isTrue,
    );
    final open = editOpenTask(
      existing.single,
      title: 'Prune carefully',
      notes: 'Leave leader',
      dueDate: '2026-11-01',
      eventType: ActivityType.pruning,
    );
    expect(open.id, existing.single.id);
    expect(open.planId, 'plan');
    expect(open.occurrenceOn, '2026-10-25');
  });
  test('reminders aggregate open group targets, exclude completed/undated work and respect local lead time', () {
    OrchardTask task(
      String id, {
      String? due = '2026-10-27',
      TaskStatus status = TaskStatus.open,
    }) => OrchardTask(
      id: id,
      propertyId: 'p',
      title: 'Prune',
      createdAt: date,
      dueDate: due,
      planId: 'plan',
      status: status,
    );
    final result = dueNotifications(
      [
        task('a'),
        task('b'),
        task('c', status: TaskStatus.completed),
        task('d', due: null),
      ],
      [
        {'id': 'plan', 'days': 1},
      ],
      date,
    );
    expect(result, hasLength(1));
    expect(result.single['body'], contains('2 open'));
    expect(
      result.single['time'],
      DateTime(2026, 10, 26, 9).millisecondsSinceEpoch,
    );
    expect(
      dueNotifications(
        [task('a')],
        [
          {'id': 'plan', 'days': 1},
        ],
        DateTime(2026, 10, 26, 10),
      ),
      isEmpty,
    );
  });
  test('photo queue survives failed upload and resumes without dropping source bytes', () async {
    final repo = await local();
    await repo.putRecord(repo.place.id, RecordKind.photo, 'photo', {
      'itemId': 'plant',
      'authorId': 'author',
      'storagePath': 'path',
      'image': base64Encode([1, 2, 3]),
      'state': 'pending',
    });
    final worker = PhotoQueue();
    await worker.drain(
      repo.place.id,
      await repo.watchRecords(repo.place.id, RecordKind.photo).first,
      repo,
      (p, b) async {
        throw StateError('Offline');
      },
    );
    final failed =
        (await repo.watchRecords(repo.place.id, RecordKind.photo).first).single;
    expect(failed['image'], isNotNull);
    expect(failed['state'], 'pending');
    final restarted = LocalTrialRepository.open(repo.preferences);
    Uint8List? bytes;
    await worker.drain(
      repo.place.id,
      await restarted.watchRecords(repo.place.id, RecordKind.photo).first,
      restarted,
      (p, b) async {
        bytes = b;
      },
    );
    expect(bytes, [1, 2, 3]);
    final uploaded =
        (await restarted.watchRecords(repo.place.id, RecordKind.photo).first)
            .single;
    expect(uploaded['state'], 'uploaded');
    expect(uploaded['image'], isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('yield report converts mass without adding counts to mass, filters taxonomy and escapes CSV', () {
    final rows = yieldRows([event('p')], [plant('p')], [], []);
    rows.add(
      YieldRow(
        '2026-10-25',
        'Pear, "second"',
        taxon,
        Harvest(10, HarvestUnit.count),
        'h2',
      ),
    );
    rows.add(
      YieldRow('2026-10-26', 'Pear', taxon, Harvest(1000, HarvestUnit.g), 'h3'),
    );
    final report = summarizeYield(
      rows,
      starterTaxonomy,
      year: 2026,
      monthly: true,
    );
    expect(report['2026-10']!.kilograms, 3);
    expect(report['2026-10']!.count, 10);
    expect(summarizeYield(rows, starterTaxonomy, year: 2025), isEmpty);
    expect(yieldCsv(rows), contains('"Pear, ""second"""'));
  });
}
