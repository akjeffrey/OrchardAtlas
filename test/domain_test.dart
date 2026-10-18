import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';

PlantEvent event(String date, {Harvest? harvest, ActivityType? type}) =>
    PlantEvent(
      id: 'event',
      propertyId: 'place',
      itemId: 'plant',
      authorId: 'user',
      type: type ?? ActivityType.harvest,
      occurredAt: DateTime.utc(2026),
      activityDate: date,
      recordedAt: DateTime.utc(2026),
      harvest: harvest,
    );
void main() {
  test('harvest year uses selected calendar date and normalizes mass separately from count', () {
    final events = [
      event('2026-01-01', harvest: Harvest(2, HarvestUnit.kg)),
      event('2026-12-31', harvest: Harvest(500, HarvestUnit.g)),
      event('2026-06-01', harvest: Harvest(1, HarvestUnit.lb)),
      event('2026-06-01', harvest: Harvest(12, HarvestUnit.count)),
      event('2025-12-31', harvest: Harvest(100, HarvestUnit.kg)),
      event('2027-01-01', harvest: Harvest(100, HarvestUnit.kg)),
      event('2026-07-01', type: ActivityType.removal),
      event('2026-07-01', type: ActivityType.note),
    ];
    final total = HarvestTotals.forYear(events, 2026);
    expect(total.kilograms, closeTo(2.95359237, 1e-9));
    expect(total.count, 12);
    expect(HarvestTotals.forYear(events, 2024).kilograms, 0);
  });
  test('reject invalid, nonfinite and fractional count harvest quantities', () {
    for (final q in [0.0, -1.0, double.nan, double.infinity, 1e13]) {
      expect(() => Harvest(q, HarvestUnit.kg), throwsArgumentError);
    }
    expect(() => Harvest(1.5, HarvestUnit.count), throwsArgumentError);
    expect(() => event('2026-01-01'), throwsArgumentError);
    expect(
      () => event(
        '2026-01-01',
        type: ActivityType.note,
        harvest: Harvest(1, HarvestUnit.kg),
      ),
      throwsArgumentError,
    );
  });
  test('invalid calendar dates are not normalized silently', () {
    for (final date in [
      '2026-02-29',
      '2026-02-31',
      '2026-13-01',
      '2026-1-1',
      'bad',
    ]) {
      expect(() => parseCalendarDate(date), throwsArgumentError);
    }
    expect(parseCalendarDate('2024-02-29').day, 29);
  });
  test('coordinates validate finite WGS84 values', () {
    for (final pair in [
      [91.0, 0.0],
      [0.0, -181.0],
      [double.nan, 0.0],
      [0.0, double.infinity],
    ]) {
      expect(() => Coordinates(pair[0], pair[1]), throwsArgumentError);
    }
    expect(Coordinates(-90, 180).longitude, 180);
  });
  test('taxonomy has valid ancestry and detects cycles and bad ranks', () {
    final cultivar = starterTaxonomy.taxa.firstWhere(
      (t) => t.rank == TaxonRank.cultivar,
    );
    expect(
      starterTaxonomy.ancestry(cultivar.id).map((t) => t.rank),
      TaxonRank.values,
    );
    expect(starterTaxonomy.isPlantIdentity(cultivar.id), true);
    expect(
      starterTaxonomy.isPlantIdentity(starterTaxonomy.taxa.first.id),
      false,
    );
    expect(
      () => Taxonomy(const [
        Taxon(id: 'a', name: 'A', rank: TaxonRank.group, parentId: 'a'),
      ]),
      throwsArgumentError,
    );
    expect(
      () =>
          Taxonomy(const [Taxon(id: 'a', name: 'A', rank: TaxonRank.species)]),
      throwsArgumentError,
    );
  });
  test('bulk template carries the starting location without unique identity or history', () {
    final plant = ManagedPlant(
      id: 'first',
      propertyId: 'place',
      name: ' Gala ',
      taxonId: 'taxon',
      location: Coordinates(51, 1),
      createdAt: DateTime.utc(2026),
    );
    expect(plant.template.name, 'Gala');
    expect(plant.template.taxonId, 'taxon');
    expect(plant.template.location?.latitude, 51);
    expect(plant.template.location?.longitude, 1);
    expect(
      () => ManagedPlant(
        id: 'x',
        propertyId: 'p',
        name: ' ',
        taxonId: 't',
        location: Coordinates(0, 0),
        createdAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
  });
}
