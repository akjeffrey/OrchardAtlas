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

  bool isPlantIdentity(String id) =>
      byId(id).rank.index >= TaxonRank.species.index;
}

// Curated starter catalog. IDs are stable UUIDs; labels may evolve independently.
final starterTaxonomy = Taxonomy(const [
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
]);
