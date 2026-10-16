import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom taxonomy, icon and dated planting survive an offline restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalTrialRepository.open(prefs);
      final pear = starterTaxonomy.taxa.firstWhere(
        (t) => t.name == 'European pear',
      );
      final taxon = Taxon(
        id: 'conference',
        name: 'Conference',
        rank: TaxonRank.cultivar,
        parentId: pear.id,
        symbol: PlantSymbol.pear,
      );
      repo.saveTaxon(repo.place.id, taxon);
      final commands = OrchardCommands(
        repo,
        Taxonomy([...starterTaxonomy.taxa, taxon]),
      );
      final plant = commands.addPlant(
        place: repo.place,
        name: ' ',
        taxonId: taxon.id,
        location: Coordinates(51, 1),
        plantingDate: DateTime(2020, 4, 10),
        authorId: LocalTrialRepository.userId,
      );
      await repo
          .watchPlants(repo.place.id)
          .firstWhere((s) => !s.hasPendingWrites);
      final restarted = LocalTrialRepository.open(prefs);
      expect(restarted.plants.single.name, 'Conference');
      expect(restarted.taxa.single.symbol, PlantSymbol.pear);
      expect(restarted.events.single.itemId, plant.id);
      expect(restarted.events.single.activityDate, '2020-04-10');
      expect(restarted.events.single.type, ActivityType.planting);
      expect(HarvestTotals.forYear(restarted.events, 2020).kilograms, 0);
    },
  );
  test('existing trial records load without a custom taxonomy field', () async {
    SharedPreferences.setMockInitialValues({
      LocalTrialRepository.storageKey: jsonEncode({
        'createdAt': '2026-10-16T12:00:00Z',
        'events': [],
        'plants': [
          {
            'id': 'old',
            'name': 'Existing apple',
            'taxonId': starterTaxonomy.taxa[2].id,
            'latitude': 51,
            'longitude': 1,
            'createdAt': '2026-10-16T12:00:00Z',
          },
        ],
      }),
    });
    final repo = LocalTrialRepository.open(
      await SharedPreferences.getInstance(),
    );
    expect(repo.plants.single.name, 'Existing apple');
    expect(repo.taxa, isEmpty);
  });
}
