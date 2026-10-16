import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/data/firestore_orchard_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<FirestoreOrchardRepository> repository(
    FakeFirebaseFirestore store,
  ) async {
    SharedPreferences.setMockInitialValues({});
    return FirestoreOrchardRepository(
      store,
      await SharedPreferences.getInstance(),
    );
  }

  test(
    'default property is stable and scoped to authenticated owner',
    () async {
      final store = FakeFirebaseFirestore();
      final repo = await repository(store);
      final first = await repo.openDefaultPlace('alice');
      final second = await repo.openDefaultPlace('alice');
      final other = await repo.openDefaultPlace('bob');
      expect(second.id, first.id);
      expect(other.id, isNot(first.id));
      expect((await store.collection('properties').get()).docs.length, 2);
    },
  );
  test(
    'cached default place opens when all network reads are unavailable',
    () async {
      final store = FakeFirebaseFirestore();
      final repo = await repository(store);
      final place = await repo.openDefaultPlace('alice');
      whenCalling(
            Invocation.method(#get, [
              predicate<Object?>(
                (options) =>
                    options is! GetOptions || options.source != Source.cache,
              ),
            ]),
          )
          .on(store.collection('properties').doc(place.id))
          .thenThrow(
            FirebaseException(plugin: 'firestore', code: 'unavailable'),
          );
      expect((await repo.openDefaultPlace('alice')).id, place.id);
    },
  );
  test(
    'a missing native cache falls back to the server for the known property',
    () async {
      final store = FakeFirebaseFirestore();
      final repo = await repository(store);
      final place = await repo.openDefaultPlace('alice');
      whenCalling(
            Invocation.method(#get, [
              isA<GetOptions>().having(
                (options) => options.source,
                'source',
                Source.cache,
              ),
            ]),
          )
          .on(store.collection('properties').doc(place.id))
          .thenThrow(
            FirebaseException(plugin: 'firestore', code: 'unavailable'),
          );
      expect((await repo.openDefaultPlace('alice')).id, place.id);
      expect((await store.collection('properties').get()).docs.length, 1);
    },
  );
  test('cache authorization errors are surfaced instead of hidden by server fallback', () async {
    final store = FakeFirebaseFirestore();
    final repo = await repository(store);
    final place = await repo.openDefaultPlace('alice');
    whenCalling(
          Invocation.method(#get, [
            isA<GetOptions>().having(
              (options) => options.source,
              'source',
              Source.cache,
            ),
          ]),
        )
        .on(store.collection('properties').doc(place.id))
        .thenThrow(
          FirebaseException(plugin: 'firestore', code: 'permission-denied'),
        );
    await expectLater(
      repo.openDefaultPlace('alice'),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
  });
  test(
    'save, bulk entry and events flow through mapped repository streams',
    () async {
      final store = FakeFirebaseFirestore();
      final repo = await repository(store);
      final place = await repo.openDefaultPlace('alice');
      var serial = 0;
      final commands = OrchardCommands(
        repo,
        starterTaxonomy,
        newId: () => 'record-${++serial}',
      );
      final species = starterTaxonomy.taxa
          .firstWhere((t) => t.rank == TaxonRank.species)
          .id;
      final first = commands.addPlant(
        place: place,
        name: 'Apple',
        taxonId: species,
        location: Coordinates(51, 1),
      );
      final second = commands.addPlant(
        place: place,
        name: first.template.name,
        taxonId: first.template.taxonId,
        location: Coordinates(51.1, 1.1),
      );
      final plants = await repo
          .watchPlants(place.id)
          .firstWhere((s) => s.value.length == 2);
      expect(plants.value.map((p) => p.id).toSet(), {first.id, second.id});
      expect(second.location.latitude, 51.1);
      commands.record(
        place: place,
        itemId: first.id,
        authorId: 'alice',
        type: ActivityType.harvest,
        date: DateTime(2026, 12, 31),
        notes: 'Good crop',
        harvest: Harvest(500, HarvestUnit.g),
      );
      final events = await repo
          .watchEvents(place.id, first.id)
          .firstWhere((s) => s.value.isNotEmpty);
      expect(HarvestTotals.forYear(events.value, 2026).kilograms, 0.5);
      expect(
        (await repo.watchEvents(place.id, second.id).first).value,
        isEmpty,
      );
      final newRepo = FirestoreOrchardRepository(
        store,
        await SharedPreferences.getInstance(),
      );
      expect((await newRepo.watchPlants(place.id).first).value.length, 2);
    },
  );
  test(
    'delayed write rejection is reported without holding up command',
    () async {
      final store = FakeFirebaseFirestore(
        securityRules: '''
      service cloud.firestore { match /databases/{database}/documents {
        match /{document=**} { allow read: if true; allow write: if false; }
      }}''',
      );
      final repo = await repository(store);
      final failure = repo.writeFailures.first;
      repo.savePlant(
        ManagedPlant(
          id: 'rejected',
          propertyId: 'p',
          name: 'Apple',
          taxonId: 't',
          location: Coordinates(51, 1),
          createdAt: DateTime.utc(2026),
        ),
      );
      expect((await failure).recordId, 'rejected');
    },
  );
}
