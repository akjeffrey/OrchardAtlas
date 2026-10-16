import 'models.dart';

class Taxonomy {
  Taxonomy(this.taxa) {
    if (taxa.map((t) => t.id).toSet().length != taxa.length) {
      throw ArgumentError('Duplicate taxonomy IDs');
    }
    for (final taxon in taxa) {
      requiredText(taxon.name, 'Taxonomy name');
      final path = ancestry(taxon.id);
      for (var i = 0; i < path.length; i++) {
        if (path[i].rank.index != i) {
          throw ArgumentError('Invalid taxonomy hierarchy');
        }
      }
    }
  }
  final List<Taxon> taxa;
  Taxon byId(String id) => taxa.firstWhere((t) => t.id == id);
  List<Taxon> children(String? parentId) =>
      taxa.where((t) => t.parentId == parentId).toList();
  List<Taxon> ancestry(String id) {
    final path = <Taxon>[];
    final visited = <String>{};
    String? current = id;
    while (current != null) {
      if (!visited.add(current)) throw ArgumentError('Taxonomy cycle');
      final taxon = byId(current);
      path.insert(0, taxon);
      current = taxon.parentId;
    }
    return path;
  }

  Set<String> descendants(String id) => taxa
      .where((t) => ancestry(t.id).any((a) => a.id == id))
      .map((t) => t.id)
      .toSet();

  bool isPlantIdentity(String id) =>
      byId(id).rank.index >= TaxonRank.species.index;
}

// Curated starter catalog. IDs are stable UUIDs; labels may evolve independently.
final starterTaxonomy = Taxonomy([
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000001',
    name: 'Fruit trees',
    rank: TaxonRank.group,
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000002',
    name: 'Apple (Malus)',
    symbol: PlantSymbol.apple,
    rank: TaxonRank.genus,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000001',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000003',
    name: 'Domestic apple',
    symbol: PlantSymbol.apple,
    scientificName: 'Malus domestica',
    rank: TaxonRank.species,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000002',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000004',
    name: 'Honeycrisp',
    symbol: PlantSymbol.apple,
    rank: TaxonRank.cultivar,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000003',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000005',
    name: 'Gala',
    symbol: PlantSymbol.apple,
    rank: TaxonRank.cultivar,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000003',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000006',
    name: 'Pear (Pyrus)',
    symbol: PlantSymbol.pear,
    rank: TaxonRank.genus,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000001',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000007',
    name: 'European pear',
    symbol: PlantSymbol.pear,
    scientificName: 'Pyrus communis',
    rank: TaxonRank.species,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000006',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000008',
    name: 'Berries',
    symbol: PlantSymbol.berry,
    rank: TaxonRank.group,
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000009',
    name: 'Rubus',
    symbol: PlantSymbol.berry,
    rank: TaxonRank.genus,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000008',
  ),
  Taxon(
    id: '38a0fbb0-6a36-4a48-8d17-000000000010',
    name: 'Red raspberry',
    symbol: PlantSymbol.berry,
    scientificName: 'Rubus idaeus',
    rank: TaxonRank.species,
    parentId: '38a0fbb0-6a36-4a48-8d17-000000000009',
  ),
  ...additionalStarterTaxa(),
]);

// Published allocation order: append only. Never reorder or insert before existing entries.
List<Taxon> additionalStarterTaxa() {
  var serial = 200;
  String id() =>
      '38a0fbb0-6a36-4a48-8d17-${(++serial).toString().padLeft(12, '0')}';
  final result = <Taxon>[];
  void genus(
    String name,
    String scientific,
    String parent,
    PlantSymbol symbol,
    List<String> species,
  ) {
    final genusId = id();
    result.add(
      Taxon(
        id: genusId,
        name: name,
        rank: TaxonRank.genus,
        parentId: parent,
        symbol: symbol,
      ),
    );
    for (final label in species) {
      result.add(
        Taxon(
          id: id(),
          name: label,
          rank: TaxonRank.species,
          parentId: genusId,
          scientificName: scientific,
          symbol: symbol,
        ),
      );
    }
  }

  for (final name in ['Zestar', 'Fuji']) {
    result.add(
      Taxon(
        id: id(),
        name: name,
        rank: TaxonRank.cultivar,
        parentId: '38a0fbb0-6a36-4a48-8d17-000000000003',
        symbol: PlantSymbol.apple,
      ),
    );
  }
  for (final name in ['Peach', 'Plum', 'Cherry', 'Apricot']) {
    genus(
      name,
      'Prunus',
      '38a0fbb0-6a36-4a48-8d17-000000000001',
      PlantSymbol.tree,
      ['Common $name'],
    );
  }
  result.add(
    Taxon(
      id: id(),
      name: 'Blackberry',
      rank: TaxonRank.species,
      parentId: '38a0fbb0-6a36-4a48-8d17-000000000009',
      symbol: PlantSymbol.berry,
    ),
  );
  for (final name in ['Blueberry', 'Strawberry', 'Gooseberry']) {
    genus(name, '', '38a0fbb0-6a36-4a48-8d17-000000000008', PlantSymbol.berry, [
      'Common $name',
    ]);
  }
  for (final entry in <(String, PlantSymbol, List<String>)>[
    ('Grape', PlantSymbol.vine, ['Grape']),
    ('Nut trees', PlantSymbol.nut, ['Walnut', 'Hazelnut', 'Chestnut']),
    ('Vegetables', PlantSymbol.flower, ['Tomato', 'Pepper', 'Squash']),
    (
      'Mushrooms',
      PlantSymbol.tree,
      ['Morel', 'Oyster', 'Chanterelle', 'Chicken of the Woods'],
    ),
    ('Wild plants', PlantSymbol.flower, ['Asparagus']),
    ('Other', PlantSymbol.tree, ['Other plant']),
  ]) {
    final groupId = id();
    result.add(
      Taxon(
        id: groupId,
        name: entry.$1,
        rank: TaxonRank.group,
        symbol: entry.$2,
      ),
    );
    for (final label in entry.$3) {
      genus(label, '', groupId, entry.$2, [label]);
    }
  }
  return result;
}
