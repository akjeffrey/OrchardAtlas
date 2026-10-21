import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/orchards.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/map_icons.dart';
import 'icon_mapping.dart';
import '../domain/work.dart';
import 'work_mapping.dart';
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
  final _childFailures = <StreamSubscription<dynamic>>[];
  static const catalogKey = "orchard-atlas-trial-orchards";
  Place place;
  final _plans = <TaskPlan>[];
  final List<ManagedPlant> plants;
  final List<PlantEvent> events;
  final List<Taxon> taxa;
  final icons = <MapIcon>[];
  final List<OrchardTask> tasks;
  final List<OrchardSection> sections;
  final List<CropPlanting> crops;
  final List<CropHarvest> cropHarvests;
  final _changes = StreamController<void>.broadcast();
  final _failures = StreamController<WriteFailure>.broadcast();
  Future<void> _writes = Future.value();
  int _pending = 0;
  final _backupChanges = StreamController<void>.broadcast();
  Stream<void> get backupChanges => _backupChanges.stream;
  Future<void> flushForBackup() async {
    if (preferences.getString(recordKey) == null) _persist(place.id);
    await _writes;
    if (_lastWriteError != null) {
      throw StateError('Local writes have not saved');
    }
    for (final child in _children.values) {
      await child.flushForBackup();
    }
    for (final p in recordKey == storageKey ? _places.skip(1) : <Place>[]) {
      final key = '$storageKey:orchard:${p.id}';
      if (preferences.getString(key) == null) await _for(p.id).flushForBackup();
    }
  }

  static const storageKey = 'orchard-atlas-phone-trial-v1';
  static const userId = 'local-phone-trial';

  static LocalTrialRepository open(
    SharedPreferences preferences, {
    Place? orchard,
    String? snapshot,
  }) {
    final recordKey = orchard == null
        ? storageKey
        : "$storageKey:orchard:${orchard.id}";
    final raw = snapshot ?? preferences.getString(recordKey);
    final data = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    final place =
        orchard ??
        Place(
          id: '38a0fbb0-6a36-4a48-8d17-000000000101',
          name: data?['name'] as String? ?? 'Home Orchard',
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
          rowOrder: (p['rowOrder'] as num?)?.toDouble(),
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
          taskId: e['taskId'] as String?,
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
          planId: t['planId'] as String?,
          occurrenceOn: t['occurrenceOn'] as String?,
          eventType: t['eventType'] == null
              ? null
              : ActivityType.values.byName(t['eventType'] as String),
          eventHarvest: t['eventHarvest'] == null
              ? null
              : Harvest(
                  (t['eventHarvest']['quantity'] as num).toDouble(),
                  HarvestUnit.values.byName(
                    t['eventHarvest']['unit'] as String,
                  ),
                ),
          title: t['title'] as String,
          notes: t['notes'] as String,
          itemId: t['itemId'] as String?,
          dueDate: t['dueDate'] as String?,
          status: TaskStatus.values.byName(t['status'] as String),
          createdAt: DateTime.parse(t['createdAt'] as String),
        ),
    ];
    final repo = LocalTrialRepository._(
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
    repo._plans.addAll([
      for (final p in data?['taskPlans'] as List? ?? [])
        WorkMapping.readPlan(
          place.id,
          p['id'] as String,
          Map<String, dynamic>.from(p as Map),
        ),
    ]);
    repo.icons.addAll([
      for (final icon in data?['icons'] as List? ?? [])
        IconMapping.read(
          icon['id'] as String,
          Map<String, dynamic>.from(icon as Map),
        ),
    ]);
    if (repo.icons.where((i) => !i.deleted).length > MapIcon.maxPerOrchard ||
        repo.icons.map((i) => i.id).toSet().length != repo.icons.length) {
      throw const FormatException('Invalid icon library');
    }
    if (taxa.map((t) => t.id).toSet().length != taxa.length) {
      throw const FormatException('Duplicate taxonomy IDs');
    }
    orchardTaxonomy(taxa);
    final iconIds = repo.icons.map((i) => i.id).toSet();
    if ([
      ...taxa.map((t) => t.customIconId),
      ...repo.sections.map((s) => s.customIconId),
    ].whereType<String>().any((id) => !iconIds.contains(id))) {
      throw const FormatException('Missing assigned icon');
    }
    return repo;
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
      throw StateError('Wrong local user');
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
      _childFailures.add(
        child.backupChanges.listen((_) => _backupChanges.add(null)),
      );
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
    _backupChanges.add(null);
    return created;
  }

  @override
  Future<Place> renamePlace(String userId, String placeId, String name) async {
    _owner(userId);
    final old = _places.firstWhere((p) => p.id == placeId);
    final renamed = Place(
      id: old.id,
      name: name,
      ownerId: old.ownerId,
      createdAt: old.createdAt,
    );
    if (placeId == place.id) {
      place = renamed;
      _persist(placeId);
      await _writes;
    } else {
      final all = [
        for (final p in _places.skip(1)) p.id == placeId ? renamed : p,
      ];
      if (!await preferences.setString(
        catalogKey,
        jsonEncode([
          for (final p in all)
            {
              'id': p.id,
              'name': p.name,
              'createdAt': p.createdAt.toIso8601String(),
            },
        ]),
      )) {
        throw StateError('Could not save name');
      }
      _children[placeId]?.place = renamed;
    }
    _changes.add(null);
    _backupChanges.add(null);
    return renamed;
  }

  @override
  Future<void> selectPlace(String userId, String placeId) async {
    _owner(userId);
    _for(placeId);
    if (!await preferences.setString('trial-selected:$userId', placeId)) {
      throw StateError('Could not save orchard selection');
    }
    _backupChanges.add(null);
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

  Object? _lastWriteError;

  void _persist(String recordId) {
    final json = jsonEncode({
      'createdAt': place.createdAt.toIso8601String(),
      'name': place.name,
      'taskPlans': [
        for (final p in _plans) {'id': p.id, ...WorkMapping.plan(p)},
      ],
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
      'icons': [
        for (final icon in icons) {'id': icon.id, ...IconMapping.write(icon)},
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
            'taskId': e.taskId,
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
        _lastWriteError = null;
        _backupChanges.add(null);
      } catch (error) {
        _lastWriteError = error;
        _failures.add(
          WriteFailure(
            recordId,
            'Could not save data on this phone. Keep the app open and try again.',
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
      throw ArgumentError('Unknown orchard');
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
    validateTaxonEdit(orchardTaxonomy(taxa), taxon);
    if (taxon.customIconId != null &&
        !icons.any((i) => i.id == taxon.customIconId)) {
      throw ArgumentError('Choose an available icon');
    }
    taxa.removeWhere((t) => t.id == taxon.id);
    taxa.add(taxon);
    _persist(taxon.id);
  }

  @override
  Stream<List<MapIcon>> watchIcons(String propertyId) => propertyId != place.id
      ? _for(propertyId).watchIcons(propertyId)
      : _watch(() => List<MapIcon>.of(icons)).map((s) => s.value);
  @override
  void saveIcon(String propertyId, MapIcon icon) {
    if (propertyId != place.id) {
      return _for(propertyId).saveIcon(propertyId, icon);
    }
    if (icons.any((i) => i.id == icon.id && i.deleted)) {
      throw StateError('Deleted icon IDs cannot be reused');
    }
    if (!icons.any((i) => i.id == icon.id) &&
        icons.where((i) => !i.deleted).length >= MapIcon.maxPerOrchard) {
      throw StateError('An orchard can contain up to 128 custom icons');
    }
    icons.removeWhere((i) => i.id == icon.id);
    icons.add(icon);
    _persist(icon.id);
  }

  @override
  void renameIcon(String propertyId, String iconId, String name) {
    if (propertyId != place.id) {
      return _for(propertyId).renameIcon(propertyId, iconId, name);
    }
    final index = icons.indexWhere((i) => i.id == iconId);
    if (index < 0) throw ArgumentError('Unknown icon');
    icons[index] = icons[index].renamed(name);
    _persist(iconId);
  }

  @override
  void deleteIcon(String propertyId, String iconId) {
    if (propertyId != place.id) {
      return _for(propertyId).deleteIcon(propertyId, iconId);
    }
    if (!icons.any((i) => i.id == iconId)) throw ArgumentError('Unknown icon');
    icons.removeWhere((i) => i.id == iconId);
    icons.add(MapIcon.deleted(id: iconId));
    _persist(iconId);
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
    if (old.createdAt != plant.createdAt) {
      throw ArgumentError('Plant creation identity is immutable');
    }
    if (plant.sectionId != null &&
        !sections.any((s) => s.id == plant.sectionId)) {
      throw ArgumentError('Unknown section');
    }
    plants[index] = plant;
    if (old.plantedOn != plant.plantedOn) {
      final planting = events
          .where(
            (e) =>
                e.itemId == plant.id &&
                e.type == ActivityType.planting &&
                e.taskId == null,
          )
          .firstOrNull;
      if (planting != null) {
        events.remove(planting);
        if (plant.plantedOn != null) {
          events.add(
            PlantEvent(
              id: planting.id,
              propertyId: plant.propertyId,
              itemId: plant.id,
              authorId: planting.authorId,
              type: ActivityType.planting,
              occurredAt: parseCalendarDate(plant.plantedOn!).toUtc(),
              activityDate: plant.plantedOn!,
              recordedAt: planting.recordedAt,
              notes: planting.notes,
            ),
          );
        }
      } else if (plant.plantedOn != null) {
        events.add(
          PlantEvent(
            id: const Uuid().v4(),
            propertyId: plant.propertyId,
            itemId: plant.id,
            authorId: userId,
            type: ActivityType.planting,
            occurredAt: parseCalendarDate(plant.plantedOn!).toUtc(),
            activityDate: plant.plantedOn!,
            recordedAt: DateTime.now().toUtc(),
          ),
        );
      }
    }
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
    if (section.customIconId != null &&
        !icons.any((i) => i.id == section.customIconId)) {
      throw ArgumentError('Choose an available icon');
    }
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
  Stream<List<TaskPlan>> watchTaskPlans(String propertyId) =>
      propertyId != place.id
      ? _for(propertyId).watchTaskPlans(propertyId)
      : _watch(() => List<TaskPlan>.of(_plans)).map((s) => s.value);
  @override
  void saveTaskPlan(TaskPlan plan) {
    if (plan.propertyId != place.id) {
      return _for(plan.propertyId).saveTaskPlan(plan);
    }
    _plans.removeWhere((p) => p.id == plan.id);
    _plans.add(plan);
    _persist(plan.id);
  }

  @override
  void saveTaskWithEvent(OrchardTask task, PlantEvent? event) {
    if (task.propertyId != place.id) {
      return _for(task.propertyId).saveTaskWithEvent(task, event);
    }
    _validateTask(task);
    if (event != null &&
        (event.taskId != task.id ||
            event.itemId != task.itemId ||
            event.propertyId != task.propertyId)) {
      throw ArgumentError('Invalid completion event');
    }
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index < 0) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    events.removeWhere((e) => e.taskId == task.id);
    if (event != null) events.add(event);
    _persist(task.id);
  }

  @override
  void updateEvent(PlantEvent event) {
    if (event.propertyId != place.id) {
      return _for(event.propertyId).updateEvent(event);
    }
    final index = events.indexWhere(
      (e) => e.id == event.id && e.itemId == event.itemId,
    );
    if (index < 0) throw StateError('Activity unavailable');
    if (events[index].taskId != event.taskId ||
        events[index].authorId != event.authorId ||
        events[index].recordedAt != event.recordedAt) {
      throw ArgumentError('Event identity is immutable');
    }
    events[index] = event;
    _persist(event.id);
  }

  @override
  void deleteEvent(PlantEvent event) {
    if (event.propertyId != place.id) {
      return _for(event.propertyId).deleteEvent(event);
    }
    events.removeWhere((e) => e.id == event.id && e.itemId == event.itemId);
    if (event.taskId != null) {
      final i = tasks.indexWhere((t) => t.id == event.taskId);
      if (i >= 0) tasks[i] = tasks[i].withStatus(TaskStatus.open);
    }
    _persist(event.id);
  }

  @override
  Future<void> deletePlant(String propertyId, String id) async {
    if (propertyId != place.id) {
      return _for(propertyId).deletePlant(propertyId, id);
    }
    plants.removeWhere((p) => p.id == id);
    events.removeWhere((e) => e.itemId == id);
    tasks.removeWhere((t) => t.itemId == id);
    _plans.removeWhere((p) => p.itemId == id);
    _persist(id);
    await _writes;
    if (_lastWriteError != null) throw StateError('Could not persist deletion');
  }

  @override
  Future<void> deleteSection(String propertyId, String id) async {
    if (propertyId != place.id) {
      return _for(propertyId).deleteSection(propertyId, id);
    }
    final ids = sectionDescendants(id, sections);
    final plantIds = plants
        .where((p) => ids.contains(p.sectionId))
        .map((p) => p.id)
        .toSet();
    final cropIds = crops
        .where((c) => ids.contains(c.sectionId))
        .map((c) => c.id)
        .toSet();
    plants.removeWhere((p) => plantIds.contains(p.id));
    events.removeWhere((e) => plantIds.contains(e.itemId));
    final deletedPlans = _plans
        .where(
          (p) =>
              plantIds.contains(p.itemId) ||
              ids.contains(p.sectionId) ||
              cropIds.contains(p.cropId),
        )
        .map((p) => p.id)
        .toSet();
    final deletedTasks = tasks
        .where((t) => deletedPlans.contains(t.planId))
        .map((t) => t.id)
        .toSet();
    events.removeWhere((e) => deletedTasks.contains(e.taskId));
    tasks.removeWhere(
      (t) =>
          deletedPlans.contains(t.planId) ||
          plantIds.contains(t.itemId) ||
          ids.contains(t.sectionId) ||
          cropIds.contains(t.cropId),
    );
    _plans.removeWhere(
      (p) =>
          plantIds.contains(p.itemId) ||
          ids.contains(p.sectionId) ||
          cropIds.contains(p.cropId),
    );
    sections.removeWhere((s) => ids.contains(s.id));
    crops.removeWhere((c) => cropIds.contains(c.id));
    cropHarvests.removeWhere((h) => cropIds.contains(h.cropId));
    _persist(id);
    await _writes;
    if (_lastWriteError != null) throw StateError('Could not persist deletion');
  }

  @override
  void saveRowOrder(String propertyId, String sectionId, List<String> ids) {
    if (propertyId != place.id) {
      return _for(propertyId).saveRowOrder(propertyId, sectionId, ids);
    }
    final members = plants
        .where((p) => p.sectionId == sectionId)
        .map((p) => p.id)
        .toSet();
    if (ids.toSet().length != ids.length ||
        !members.containsAll(ids) ||
        ids.length != members.length) {
      throw ArgumentError('Order must include every row plant');
    }
    for (var i = 0; i < ids.length; i++) {
      final index = plants.indexWhere((p) => p.id == ids[i]);
      plants[index] = plants[index].copyWith(rowOrder: i.toDouble());
    }
    _persist(sectionId);
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
    _plans.clear();
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
      throw UnsupportedError('This installation uses local data');
  @override
  Future<void> register(String email, String password) async =>
      throw UnsupportedError('This installation uses local data');
  @override
  Future<void> signOut() async {}
}
