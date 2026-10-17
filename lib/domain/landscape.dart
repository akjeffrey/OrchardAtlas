import 'models.dart';
import 'taxonomy.dart';

enum SectionKind { area, row }

enum CropStatus { growing, harvested, ended }

class OrchardSection {
  OrchardSection({
    required this.id,
    required this.propertyId,
    required String name,
    required this.kind,
    required List<Coordinates> vertices,
    required this.createdAt,
    this.parentId,
    this.color = 0xff4caf50,
    this.symbol,
    String notes = '',
  }) : name = requiredText(name, 'Section name'),
       vertices = List.unmodifiable(vertices),
       notes = optionalText(notes, 10000) {
    if (color < 0 || color > 0xffffffff) throw ArgumentError('Invalid color');
    validateGeometry(kind, vertices);
    if (parentId == id) throw ArgumentError('A section cannot contain itself');
  }
  final int color;
  final PlantSymbol? symbol;
  final String id, propertyId, name, notes;
  final String? parentId;
  final SectionKind kind;
  final List<Coordinates> vertices;
  final DateTime createdAt;
  OrchardSection edited({
    required String name,
    required String notes,
    required List<Coordinates> vertices,
    int? color,
    PlantSymbol? symbol,
    bool clearSymbol = false,
  }) => OrchardSection(
    id: id,
    propertyId: propertyId,
    name: name,
    notes: notes,
    kind: kind,
    parentId: parentId,
    color: color ?? this.color,
    symbol: clearSymbol ? null : symbol ?? this.symbol,
    vertices: vertices,
    createdAt: createdAt,
  );
}

void validateGeometry(SectionKind kind, List<Coordinates> points) {
  final minimum = kind == SectionKind.row ? 2 : 3;
  if (points.length < minimum || points.length > 40) {
    throw ArgumentError('Use $minimum–40 vertices');
  }
  final keys = points.map((p) => '${p.latitude},${p.longitude}').toSet();
  if (keys.length != points.length) {
    throw ArgumentError(
      'Vertices must be distinct; polygon closure is automatic',
    );
  }
  final lons = points.map((p) => p.longitude).toList()..sort();
  if (lons.last - lons.first > 180) {
    throw ArgumentError('Shapes crossing the date line are not supported');
  }
  if (kind == SectionKind.row) return;
  double cross(Coordinates a, Coordinates b, Coordinates c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
  bool between(double x, double a, double b) =>
      x >= (a < b ? a : b) - 1e-12 && x <= (a > b ? a : b) + 1e-12;
  bool on(Coordinates a, Coordinates b, Coordinates p) =>
      cross(a, b, p).abs() < 1e-14 &&
      between(p.latitude, a.latitude, b.latitude) &&
      between(p.longitude, a.longitude, b.longitude);
  bool intersects(Coordinates a, Coordinates b, Coordinates c, Coordinates d) =>
      (cross(a, b, c) * cross(a, b, d) < 0 &&
          cross(c, d, a) * cross(c, d, b) < 0) ||
      on(a, b, c) ||
      on(a, b, d) ||
      on(c, d, a) ||
      on(c, d, b);
  var area = 0.0;
  final origin = points.first;
  for (var i = 0; i < points.length; i++) {
    area += cross(origin, points[i], points[(i + 1) % points.length]);
    for (var j = i + 1; j < points.length; j++) {
      if (j == i + 1 || (i == 0 && j == points.length - 1)) continue;
      if (intersects(
        points[i],
        points[(i + 1) % points.length],
        points[j],
        points[(j + 1) % points.length],
      )) {
        throw ArgumentError('Polygon edges cannot intersect');
      }
    }
  }
  if (area.abs() < 1e-14) {
    throw ArgumentError('An area needs non-collinear vertices');
  }
}

Set<String> sectionDescendants(String id, Iterable<OrchardSection> sections) {
  final result = <String>{id};
  var changed = true;
  while (changed) {
    changed = false;
    for (final section in sections) {
      if (result.contains(section.parentId) && result.add(section.id)) {
        changed = true;
      }
    }
  }
  return result;
}

void validateSectionParent(
  OrchardSection section,
  List<OrchardSection> sections,
) {
  final visited = <String>{section.id};
  var parent = section.parentId;
  while (parent != null) {
    if (!visited.add(parent)) throw ArgumentError('Section hierarchy cycle');
    final found = sections
        .where((s) => s.id == parent && s.propertyId == section.propertyId)
        .firstOrNull;
    if (found == null || found.kind == SectionKind.row) {
      throw ArgumentError('Parent must be an Area in this property');
    }
    parent = found.parentId;
  }
}

class CropPlanting {
  CropPlanting({
    required this.id,
    required this.propertyId,
    required this.sectionId,
    required this.taxonId,
    required String label,
    required String season,
    required this.createdAt,
    this.plantedOn,
    this.harvestedOn,
    this.status = CropStatus.growing,
    String notes = '',
  }) : label = requiredText(label, 'Crop label'),
       season = requiredText(season, 'Season'),
       notes = optionalText(notes, 10000) {
    if (plantedOn != null) parseCalendarDate(plantedOn!);
    if (harvestedOn != null) parseCalendarDate(harvestedOn!);
    if (status == CropStatus.harvested && harvestedOn == null) {
      throw ArgumentError('Harvest completion date required');
    }
    if (plantedOn != null &&
        harvestedOn != null &&
        harvestedOn!.compareTo(plantedOn!) < 0) {
      throw ArgumentError('Harvest date precedes planting');
    }
  }
  final String id, propertyId, sectionId, taxonId, label, season, notes;
  final String? plantedOn, harvestedOn;
  final DateTime createdAt;
  final CropStatus status;
  CropPlanting finish(CropStatus status, {String? date}) {
    if (this.status == CropStatus.ended || status == CropStatus.growing) {
      throw ArgumentError('Start a new planting for a new season');
    }
    return CropPlanting(
      id: id,
      propertyId: propertyId,
      sectionId: sectionId,
      taxonId: taxonId,
      label: label,
      season: season,
      createdAt: createdAt,
      plantedOn: plantedOn,
      harvestedOn: date ?? harvestedOn,
      status: status,
      notes: notes,
    );
  }
}

class CropHarvest {
  CropHarvest({
    required this.id,
    required this.propertyId,
    required this.cropId,
    required this.activityDate,
    required this.harvest,
    required this.recordedAt,
    String notes = '',
  }) : notes = optionalText(notes, 10000) {
    parseCalendarDate(activityDate);
  }
  final String id, propertyId, cropId, activityDate, notes;
  final Harvest harvest;
  final DateTime recordedAt;
}

List<OrchardTask> groupPlantTasks({
  required String propertyId,
  required String title,
  required List<ManagedPlant> plants,
  required Taxonomy taxonomy,
  required List<OrchardSection> sections,
  required String Function() newId,
  String? taxonId,
  String? sectionId,
  String? dueDate,
  String notes = '',
}) {
  final taxonIds = taxonId == null ? null : taxonomy.descendants(taxonId);
  final sectionIds = sectionId == null
      ? null
      : sectionDescendants(sectionId, sections);
  final targets = plants
      .where(
        (p) =>
            p.propertyId == propertyId &&
            p.status == ItemStatus.active &&
            (taxonIds == null || taxonIds.contains(p.taxonId)) &&
            (sectionIds == null || sectionIds.contains(p.sectionId)),
      )
      .toList();
  if (targets.isEmpty || targets.length > 400) {
    throw ArgumentError('Select 1–400 matching active plants');
  }
  final group = newId(), now = DateTime.now().toUtc();
  final scope =
      '${taxonId == null ? 'All classifications' : taxonomy.byId(taxonId).name}${sectionId == null ? '' : ' · ${sections.firstWhere((s) => s.id == sectionId).name}'}';
  return [
    for (final plant in targets)
      OrchardTask(
        id: newId(),
        propertyId: propertyId,
        title: title,
        itemId: plant.id,
        groupId: group,
        groupScope: scope,
        dueDate: dueDate,
        notes: notes,
        createdAt: now,
      ),
  ];
}

List<OrchardTask> groupLayoutTasks({
  required String propertyId,
  required String title,
  required List<OrchardSection> sections,
  required List<CropPlanting> crops,
  required Taxonomy taxonomy,
  required String Function() newId,
  required bool targetCrops,
  SectionKind kind = SectionKind.row,
  String? sectionId,
  String? taxonId,
  String? dueDate,
  String notes = '',
}) {
  final descendants = sectionId == null
      ? null
      : sectionDescendants(sectionId, sections);
  final taxonIds = taxonId == null ? null : taxonomy.descendants(taxonId);
  final rows = sections
      .where(
        (s) =>
            s.propertyId == propertyId &&
            s.kind == kind &&
            (descendants == null || descendants.contains(s.id)),
      )
      .toList();
  final plantings = crops
      .where(
        (c) =>
            c.propertyId == propertyId &&
            c.status == CropStatus.growing &&
            (descendants == null || descendants.contains(c.sectionId)) &&
            (taxonIds == null || taxonIds.contains(c.taxonId)),
      )
      .toList();
  final count = targetCrops ? plantings.length : rows.length;
  if (count == 0 || count > 400) {
    throw ArgumentError('Select 1–400 matching targets');
  }
  final group = newId(), now = DateTime.now().toUtc();
  final scope =
      '${targetCrops ? 'Seasonal crops' : kind.name}${sectionId == null ? ' · whole property' : ' · ${sections.firstWhere((s) => s.id == sectionId).name}'}';
  return targetCrops
      ? [
          for (final c in plantings)
            OrchardTask(
              id: newId(),
              propertyId: propertyId,
              title: title,
              cropId: c.id,
              groupId: group,
              groupScope: scope,
              dueDate: dueDate,
              notes: notes,
              createdAt: now,
            ),
        ]
      : [
          for (final s in rows)
            OrchardTask(
              id: newId(),
              propertyId: propertyId,
              title: title,
              sectionId: s.id,
              groupId: group,
              groupScope: scope,
              dueDate: dueDate,
              notes: notes,
              createdAt: now,
            ),
        ];
}
