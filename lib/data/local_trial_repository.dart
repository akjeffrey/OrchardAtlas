import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

/// Explicit phone-trial storage; never connects to a Firebase project.
class LocalTrialRepository implements OrchardRepository {
  LocalTrialRepository._(
    this.preferences,
    this.place,
    this.plants,
    this.events,
  );
  final SharedPreferences preferences;
  final Place place;
  final List<ManagedPlant> plants;
  final List<PlantEvent> events;
  final _changes = StreamController<void>.broadcast();
  final _failures = StreamController<WriteFailure>.broadcast();
  Future<void> _writes = Future.value();
  int _pending = 0;
  static const storageKey = 'orchard-atlas-phone-trial-v1';
  static const userId = 'local-phone-trial';

  static LocalTrialRepository open(SharedPreferences preferences) {
    final raw = preferences.getString(storageKey);
    final data = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    final place = Place(
      id: '38a0fbb0-6a36-4a48-8d17-000000000101',
      name: 'Trial orchard',
      ownerId: userId,
      createdAt: data == null
          ? DateTime.now().toUtc()
          : DateTime.parse(data['createdAt'] as String),
    );
    final plants = <ManagedPlant>[
      for (final p in data?['plants'] as List? ?? [])
        ManagedPlant(
          id: p['id'] as String,
          propertyId: place.id,
          name: p['name'] as String,
          taxonId: p['taxonId'] as String,
          location: Coordinates(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
          createdAt: DateTime.parse(p['createdAt'] as String),
        ),
    ];
    final events = <PlantEvent>[
      for (final e in data?['events'] as List? ?? [])
        PlantEvent(
          id: e['id'] as String,
          propertyId: place.id,
          itemId: e['itemId'] as String,
          authorId: userId,
          type: ActivityType.values.byName(e['type'] as String),
          occurredAt: DateTime.parse(e['occurredAt'] as String),
          activityDate: e['activityDate'] as String,
          recordedAt: DateTime.parse(e['recordedAt'] as String),
          notes: e['notes'] as String,
          harvest: e['harvest'] == null
              ? null
              : Harvest(
                  (e['harvest']['quantity'] as num).toDouble(),
                  HarvestUnit.values.byName(e['harvest']['unit'] as String),
                ),
        ),
    ];
    return LocalTrialRepository._(preferences, place, plants, events);
  }

  @override
  Future<Place> openDefaultPlace(String userId) async => place;
  Stream<RepositorySnapshot<List<T>>> _watch<T>(List<T> Function() read) =>
      Stream.multi((controller) {
        void emit() => controller.add(
          RepositorySnapshot(
            read(),
            isFromCache: true,
            hasPendingWrites: _pending > 0,
          ),
        );
        emit();
        final subscription = _changes.stream.listen((_) => emit());
        controller.onCancel = subscription.cancel;
      });
  @override
  Stream<RepositorySnapshot<List<ManagedPlant>>> watchPlants(
    String propertyId,
  ) => _watch(
    () =>
        plants.where((p) => p.propertyId == propertyId).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
  );
  @override
  Stream<RepositorySnapshot<List<PlantEvent>>> watchEvents(
    String propertyId,
    String itemId,
  ) => _watch(
    () =>
        events
            .where((e) => e.propertyId == propertyId && e.itemId == itemId)
            .toList()
          ..sort((a, b) => b.activityDate.compareTo(a.activityDate)),
  );
  @override
  Stream<WriteFailure> get writeFailures => _failures.stream;

  void _persist(String recordId) {
    final json = jsonEncode({
      'createdAt': place.createdAt.toIso8601String(),
      'plants': [
        for (final p in plants)
          {
            'id': p.id,
            'name': p.name,
            'taxonId': p.taxonId,
            'latitude': p.location.latitude,
            'longitude': p.location.longitude,
            'createdAt': p.createdAt.toIso8601String(),
          },
      ],
      'events': [
        for (final e in events)
          {
            'id': e.id,
            'itemId': e.itemId,
            'type': e.type.name,
            'notes': e.notes,
            'occurredAt': e.occurredAt.toIso8601String(),
            'activityDate': e.activityDate,
            'recordedAt': e.recordedAt.toIso8601String(),
            if (e.harvest != null)
              'harvest': {
                'quantity': e.harvest!.quantity,
                'unit': e.harvest!.unit.name,
              },
          },
      ],
    });
    _pending++;
    _changes.add(null);
    _writes = _writes.then((_) async {
      try {
        if (!await preferences.setString(storageKey, json)) {
          throw StateError('Device storage rejected write');
        }
      } catch (_) {
        _failures.add(
          WriteFailure(
            recordId,
            'Could not save trial data on this phone. Keep the app open and try again.',
          ),
        );
      } finally {
        _pending--;
        _changes.add(null);
      }
    });
  }

  @override
  void savePlant(ManagedPlant plant) {
    if (plant.propertyId != place.id) {
      throw ArgumentError('Unknown trial property');
    }
    if (plants.any((p) => p.id == plant.id)) {
      throw StateError('Plant already exists');
    }
    plants.add(plant);
    _persist(plant.id);
  }

  @override
  void appendEvent(PlantEvent event) {
    if (!plants.any(
      (p) => p.id == event.itemId && p.propertyId == event.propertyId,
    )) {
      throw StateError('Plant not found');
    }
    if (events.any((e) => e.id == event.id)) {
      throw StateError('Activity already exists');
    }
    events.add(event);
    _persist(event.id);
  }

  @override
  Future<void> clearDeviceCache() async {
    await _writes;
    await preferences.remove(storageKey);
    plants.clear();
    events.clear();
    _changes.add(null);
  }
}

class TrialAuthRepository implements AuthRepository {
  @override
  Stream<OrchardUser?> get userChanges =>
      Stream.value(const OrchardUser(LocalTrialRepository.userId));
  @override
  Future<void> signIn(String email, String password) async =>
      throw UnsupportedError('Trial uses local data');
  @override
  Future<void> register(String email, String password) async =>
      throw UnsupportedError('Trial uses local data');
  @override
  Future<void> signOut() async {}
}
