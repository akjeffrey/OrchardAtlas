import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/orchards.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/landscape.dart';
import 'landscape_mapping.dart';
import '../domain/repositories.dart';
import '../domain/taxonomy.dart';
import 'firestore_mapping.dart';

/// Explicit phone-trial storage; never connects to a Firebase project.
class LocalTrialRepository
    implements OrchardRepository, OrchardDirectoryRepository {
  LocalTrialRepository._(
    this.preferences,
    this.recordKey,
    this.place,
    this.plants,
    this.events,
    this.taxa,
    this.tasks,
    this.sections,
    this.crops,
    this.cropHarvests,
  );
  final SharedPreferences preferences;
  final String recordKey;
  final _children = <String, LocalTrialRepository>{};
  final _childFailures = <StreamSubscription<WriteFailure>>[];
  static const catalogKey = "orchard-atlas-trial-orchards";
  final Place place;
  final List<ManagedPlant> plants;
  final List<PlantEvent> events;
  final List<Taxon> taxa;
  final List<OrchardTask> tasks;
  final List<OrchardSection> sections;
  final List<CropPlanting> crops;
  final List<CropHarvest> cropHarvests;
  final _changes = StreamController<void>.broadcast();
  final _failures = StreamController<WriteFailure>.broadcast();
  Future<void> _writes = Future.value();
  int _pending = 0;
  static const storageKey = 'orchard-atlas-phone-trial-v1';
  static const userId = 'local-phone-trial';

  static LocalTrialRepository open(
    SharedPreferences preferences, {
    Place? orchard,
  }) {
    final recordKey = orchard == null
        ? storageKey
        : "$storageKey:orchard:${orchard.id}";
    final raw = preferences.getString(recordKey);
    final data = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    final place =
        orchard ??
        Place(
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
          sectionId: p['sectionId'] as String?,
          plantedOn: _readPlantedOn(p as Map, data),
          rootstock: p['rootstock'] as String? ?? '',
          nursery: p['nursery'] as String? ?? '',
          notes: p['notes'] as String? ?? '',
          status: ItemStatus.values.byName(p['status'] as String? ?? 'active'),
          accuracyMeters: (p['accuracyMeters'] as num?)?.toDouble(),
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
    final taxa = <Taxon>[
      for (final t in data?['taxa'] as List? ?? [])
        FirestoreMapping.taxonFromMap(
          t['id'] as String,
          Map<String, dynamic>.from(t as Map),
        ),
    ];
    final tasks = <OrchardTask>[
      for (final t in data?['tasks'] as List? ?? [])
        OrchardTask(
          id: t['id'] as String,
          propertyId: place.id,
          sectionId: t['sectionId'] as String?,
          cropId: t['cropId'] as String?,
          groupId: t['groupId'] as String?,
          groupScope: t['groupScope'] as String? ?? '',
          completedOn: t['completedOn'] as String?,
          title: t['title'] as String,
          notes: t['notes'] as String,
          itemId: t['itemId'] as String?,
          dueDate: t['dueDate'] as String?,
          status: TaskStatus.values.byName(t['status'] as String),
          createdAt: DateTime.parse(t['createdAt'] as String),
        ),
    ];
    return LocalTrialRepository._(
      preferences,
      recordKey,
      place,
      plants,
      events,
      taxa,
      tasks,
      [
        for (final s in data?['sections'] as List? ?? [])
          LandscapeMapping.readSection(
            place.id,
            s['id'] as String,
            Map<String, dynamic>.from(s as Map),
          ),
      ],
      [
        for (final c in data?['crops'] as List? ?? [])
          LandscapeMapping.readCrop(
            place.id,
            c['id'] as String,
            Map<String, dynamic>.from(c as Map),
          ),
      ],
      [
        for (final h in data?['cropHarvests'] as List? ?? [])
          LandscapeMapping.readHarvest(
            place.id,
            h['id'] as String,
            Map<String, dynamic>.from(h as Map),
          ),
      ],
    );
  }

  static String? _readPlantedOn(Map p, Map<String, dynamic>? data) {
    if (p.containsKey('plantedOn')) return p['plantedOn'] as String?;
    final events =
        (data?['events'] as List? ?? [])
            .where((e) => e['itemId'] == p['id'] && e['type'] == 'planting')
            .toList()
          ..sort(
            (a, b) => (a['recordedAt'] as String).compareTo(
              b['recordedAt'] as String,
            ),
          );
    return events.isEmpty ? null : events.first['activityDate'] as String;
  }

  @override
  Future<Place> openDefaultPlace(String userId) async {
    _owner(userId);
    final selected = preferences.getString('trial-selected:$userId');
    return _places.where((p) => p.id == selected).firstOrNull ?? place;
  }

  void _owner(String userId) {
    if (userId != LocalTrialRepository.userId) {
      throw StateError('Wrong trial user');
    }
  }

  List<Place> get _places => [
    place,
    for (final p
        in jsonDecode(preferences.getString(catalogKey) ?? '[]') as List)
      Place(
        id: p['id'] as String,
        name: p['name'] as String,
        ownerId: userId,
        createdAt: DateTime.parse(p['createdAt'] as String),
      ),
  ];
  LocalTrialRepository _for(String id) {
    if (id == place.id) return this;
    return _children.putIfAbsent(id, () {
      final target = _places.where((p) => p.id == id).firstOrNull;
      if (target == null) throw ArgumentError('Unknown orchard');
      final child = LocalTrialRepository.open(preferences, orchard: target);
      _childFailures.add(child.writeFailures.listen(_failures.add));
      return child;
    });
  }

  @override
  Stream<List<Place>> watchPlaces(String userId) {
    _owner(userId);
    return _watch(() => _places).map((s) => s.value);
  }

  @override
  Future<Place> createPlace(String userId, String name) async {
    _owner(userId);
    final created = Place(
      id: const Uuid().v4(),
      name: requiredText(name, 'Orchard name'),
      ownerId: userId,
      createdAt: DateTime.now().toUtc(),
    );
    final places = [..._places.skip(1), created];
    if (!await preferences.setString(
      catalogKey,
      jsonEncode([
        for (final p in places)
          {
            'id': p.id,
            'name': p.name,
            'createdAt': p.createdAt.toIso8601String(),
          },
      ]),
    )) {
      throw StateError('Could not save orchard');
    }
    _changes.add(null);
    return created;
  }

  @override
  Future<void> selectPlace(String userId, String placeId) async {
    _owner(userId);
    _for(placeId);
    if (!await preferences.setString('trial-selected:$userId', placeId)) {
      throw StateError('Could not save orchard selection');
    }
  }

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
  ) => propertyId != place.id
      ? _for(propertyId).watchPlants(propertyId)
      : _watch(
          () =>
              plants.where((p) => p.propertyId == propertyId).toList()
                ..sort((a, b) => a.name.compareTo(b.name)),
        );
  @override
  Stream<RepositorySnapshot<List<PlantEvent>>> watchEvents(
    String propertyId,
    String itemId,
  ) => propertyId != place.id
      ? _for(propertyId).watchEvents(propertyId, itemId)
      : _watch(
          () =>
              events
                  .where(
                    (e) => e.propertyId == propertyId && e.itemId == itemId,
                  )
                  .toList()
                ..sort((a, b) => b.activityDate.compareTo(a.activityDate)),
        );
  @override
  Stream<WriteFailure> get writeFailures => _failures.stream;

  void _persist(String recordId) {
    final json = jsonEncode({
      'createdAt': place.createdAt.toIso8601String(),
      'sections': [
        for (final s in sections) {'id': s.id, ...LandscapeMapping.section(s)},
      ],
      'crops': [
        for (final c in crops) {'id': c.id, ...LandscapeMapping.crop(c)},
      ],
      'cropHarvests': [
        for (final h in cropHarvests)
          {'id': h.id, ...LandscapeMapping.harvest(h)},
      ],
      'taxa': [
        for (final t in taxa) {'id': t.id, ...FirestoreMapping.taxonToMap(t)},
      ],
      'plants': [
        for (final p in plants)
          {
            'id': p.id,
            'name': p.name,
            'taxonId': p.taxonId,
            'latitude': p.location.latitude,
            'longitude': p.location.longitude,
            'createdAt': p.createdAt.toIso8601String(),
            ...FirestoreMapping.plantMetadataToMap(p),
          },
      ],
      'tasks': [
        for (final t in tasks)
          {
            'id': t.id,
            ...FirestoreMapping.taskExtrasToMap(t),
            'title': t.title,
            'notes': t.notes,
            'itemId': t.itemId,
            'dueDate': t.dueDate,
            'status': t.status.name,
            'createdAt': t.createdAt.toIso8601String(),
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
        if (!await preferences.setString(recordKey, json)) {
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
  void savePlant(ManagedPlant plant, {PlantEvent? plantingEvent}) {
    if (plant.propertyId != place.id) {
      return _for(plant.propertyId)
          .savePlant(plant, plantingEvent: plantingEvent);
    }
    if (plant.propertyId != place.id) {
      throw ArgumentError('Unknown trial property');
    }
    if (plants.any((p) => p.id == plant.id)) {
      throw StateError('Plant already exists');
    }
    if (plantingEvent != null &&
        (plantingEvent.itemId != plant.id ||
            plantingEvent.propertyId != plant.propertyId)) {
      throw ArgumentError('Planting activity must belong to this plant');
    }
    if (plant.sectionId != null &&
        !sections.any((s) => s.id == plant.sectionId)) {
      throw ArgumentError('Unknown section');
    }
    plants.add(plant);
    if (plantingEvent != null) events.add(plantingEvent);
    _persist(plant.id);
  }

  @override
  Stream<List<Taxon>> watchTaxa(String propertyId) => propertyId != place.id
      ? _for(propertyId).watchTaxa(propertyId)
      : _watch(() => List<Taxon>.of(taxa)).map((s) => s.value);
  @override
  void saveTaxon(String propertyId, Taxon taxon) {
    if (propertyId != place.id) {
      return _for(propertyId).saveTaxon(propertyId, taxon);
    }
    if (propertyId != place.id) throw ArgumentError('Unknown property');
    Taxonomy([...starterTaxonomy.taxa, ...taxa, taxon]);
    taxa.add(taxon);
    _persist(taxon.id);
  }

  @override
  void appendEvent(PlantEvent event) {
    if (event.propertyId != place.id) {
      return _for(event.propertyId).appendEvent(event);
    }
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
  void updatePlant(ManagedPlant plant) {
    if (plant.propertyId != place.id) {
      return _for(plant.propertyId).updatePlant(plant);
    }
    final index = plants.indexWhere(
      (p) => p.id == plant.id && p.propertyId == plant.propertyId,
    );
    if (index < 0) throw StateError('Plant not found');
    final old = plants[index];
    if (old.createdAt != plant.createdAt ||
        old.taxonId != plant.taxonId ||
        old.plantedOn != plant.plantedOn ||
        old.location.latitude != plant.location.latitude ||
        old.location.longitude != plant.location.longitude ||
        old.accuracyMeters != plant.accuracyMeters) {
      throw ArgumentError(
        'Plant identity and capture fields cannot be changed',
      );
    }
    if (plant.sectionId != null &&
        !sections.any((s) => s.id == plant.sectionId)) {
      throw ArgumentError('Unknown section');
    }
    plants[index] = plant;
    _persist(plant.id);
  }

  @override
  Stream<RepositorySnapshot<List<OrchardTask>>> watchTasks(String propertyId) =>
      propertyId != place.id
      ? _for(propertyId).watchTasks(propertyId)
      : _watch(
          () => tasks.where((t) => t.propertyId == propertyId).toList()
            ..sort(
              (a, b) => (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'),
            ),
        );
  void _validateTask(OrchardTask task) {
    if (task.propertyId != place.id ||
        (task.itemId != null && !plants.any((p) => p.id == task.itemId)) ||
        (task.sectionId != null &&
            !sections.any((s) => s.id == task.sectionId)) ||
        (task.cropId != null && !crops.any((c) => c.id == task.cropId))) {
      throw ArgumentError('Unknown task target');
    }
    final old = tasks.where((t) => t.id == task.id).firstOrNull;
    if (old != null &&
        (old.itemId != task.itemId ||
            old.sectionId != task.sectionId ||
            old.cropId != task.cropId ||
            old.groupId != task.groupId ||
            old.groupScope != task.groupScope ||
            old.createdAt != task.createdAt ||
            old.title != task.title ||
            old.notes != task.notes ||
            old.dueDate != task.dueDate)) {
      throw ArgumentError('Only task status can be updated');
    }
  }

  @override
  void saveTask(OrchardTask task) {
    if (task.propertyId != place.id) {
      return _for(task.propertyId).saveTask(task);
    }
    _validateTask(task);
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index < 0) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    _persist(task.id);
  }

  @override
  void saveTaskGroup(List<OrchardTask> group) {
    if (group.isNotEmpty &&
        group.any((t) => t.propertyId != group.first.propertyId)) {
      throw ArgumentError('Group must belong to one orchard');
    }
    if (group.isNotEmpty && group.first.propertyId != place.id) {
      return _for(group.first.propertyId).saveTaskGroup(group);
    }
    if (group.isEmpty ||
        group.length > 400 ||
        group.first.groupId == null ||
        group.any(
          (t) =>
              t.groupId != group.first.groupId ||
              tasks.any((old) => old.id == t.id),
        ) ||
        group.map((t) => t.id).toSet().length != group.length ||
        group.map((t) => t.itemId ?? t.sectionId ?? t.cropId).toSet().length !=
            group.length) {
      throw ArgumentError('Invalid group membership');
    }
    for (final task in group) {
      _validateTask(task);
    }
    tasks.addAll(group);
    _persist(group.first.groupId!);
  }

  @override
  Stream<RepositorySnapshot<List<OrchardSection>>> watchSections(
    String propertyId,
  ) => propertyId != place.id
      ? _for(propertyId).watchSections(propertyId)
      : _watch(
          () => sections.where((s) => s.propertyId == propertyId).toList(),
        );
  @override
  void saveSection(OrchardSection section) {
    if (section.propertyId != place.id) {
      return _for(section.propertyId).saveSection(section);
    }
    if (section.propertyId != place.id) throw ArgumentError('Unknown property');
    validateSectionParent(section, sections);
    final index = sections.indexWhere((s) => s.id == section.id);
    if (index >= 0) {
      final old = sections[index];
      if (old.parentId != section.parentId ||
          old.kind != section.kind ||
          old.createdAt != section.createdAt) {
        throw ArgumentError('Section identity is immutable');
      }
      sections[index] = section;
    } else {
      sections.add(section);
    }
    _persist(section.id);
  }

  @override
  Stream<RepositorySnapshot<List<CropPlanting>>> watchCrops(
    String propertyId,
  ) => propertyId != place.id
      ? _for(propertyId).watchCrops(propertyId)
      : _watch(() => crops.where((c) => c.propertyId == propertyId).toList());
  @override
  void saveCrop(CropPlanting crop) {
    if (crop.propertyId != place.id) {
      return _for(crop.propertyId).saveCrop(crop);
    }
    if (crop.propertyId != place.id ||
        !sections.any((s) => s.id == crop.sectionId)) {
      throw ArgumentError('Unknown crop section');
    }
    final index = crops.indexWhere((c) => c.id == crop.id);
    if (index >= 0) {
      final old = crops[index];
      final a = LandscapeMapping.crop(old)
        ..remove('status')
        ..remove('harvestedOn');
      final b = LandscapeMapping.crop(crop)
        ..remove('status')
        ..remove('harvestedOn');
      if (jsonEncode(a) != jsonEncode(b) ||
          old.status == CropStatus.ended ||
          crop.status == CropStatus.growing) {
        throw ArgumentError('Create a new planting to change a season');
      }
      crops[index] = crop;
    } else {
      crops.add(crop);
    }
    _persist(crop.id);
  }

  @override
  Stream<RepositorySnapshot<List<CropHarvest>>> watchCropHarvests(
    String propertyId,
  ) => propertyId != place.id
      ? _for(propertyId).watchCropHarvests(propertyId)
      : _watch(
          () => cropHarvests.where((h) => h.propertyId == propertyId).toList(),
        );
  @override
  void appendCropHarvest(CropHarvest harvest) {
    if (harvest.propertyId != place.id) {
      return _for(harvest.propertyId).appendCropHarvest(harvest);
    }
    if (harvest.propertyId != place.id ||
        !crops.any((c) => c.id == harvest.cropId) ||
        cropHarvests.any((h) => h.id == harvest.id)) {
      throw ArgumentError('Invalid harvest target or duplicate ID');
    }
    final crop = crops.firstWhere((c) => c.id == harvest.cropId);
    if (crop.plantedOn != null &&
        harvest.activityDate.compareTo(crop.plantedOn!) < 0) {
      throw ArgumentError('Harvest date precedes planting');
    }
    cropHarvests.add(harvest);
    _persist(harvest.id);
  }

  @override
  Future<void> clearDeviceCache() async {
    await _writes;
    for (final p in _places.skip(1)) {
      await _children[p.id]?._writes;
      await preferences.remove('$storageKey:orchard:${p.id}');
    }
    for (final subscription in _childFailures) {
      await subscription.cancel();
    }
    _childFailures.clear();
    _children.clear();
    await preferences.remove(catalogKey);
    await preferences.remove('trial-selected:$userId');
    await preferences.remove(recordKey);
    plants.clear();
    events.clear();
    taxa.clear();
    tasks.clear();
    sections.clear();
    crops.clear();
    cropHarvests.clear();
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
