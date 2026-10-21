import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/taxonomy.dart';
import 'icon_picker.dart';

/// Shared catalog creation for Add Plant and Edit Plant. The option is saved
/// independently; assigning it to an existing plant remains an editor draft.
Future<Taxon?> createTaxonOption(
  BuildContext context,
  WidgetRef ref, {
  required int rank,
  required String? parentId,
}) async {
  final place = await ref.read(placeProvider.future);
  await ref.read(customTaxaProvider.future);
  if (!context.mounted) return null;
  final taxonomy = ref.read(taxonomyProvider);
  final inherited = parentId == null ? null : taxonomy.iconFor(parentId);
  var optionName = '';
  var iconOverride = false;
  var symbol = inherited?.symbol ?? PlantSymbol.tree;
  String? customIconId = inherited?.customIconId;
  String? error;
  final result = await showDialog<Taxon>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text('Add ${['Group', 'Type', 'Variety'][rank]}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                maxLength: 500,
                onChanged: (value) => optionName = value,
                decoration: InputDecoration(
                  labelText: 'Option name',
                  errorText: error,
                ),
              ),
              MapIconPicker(
                symbol: symbol,
                customIconId: customIconId,
                onChanged: (s, id) => update(() {
                  symbol = s!;
                  customIconId = id;
                  iconOverride = true;
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final proposed = Taxon(
                  id: const Uuid().v4(),
                  name: requiredText(optionName, 'Option name'),
                  rank: TaxonRank.values[rank],
                  parentId: parentId,
                  symbol: symbol,
                  customIconId: customIconId,
                  iconOverride: iconOverride,
                );
                validateTaxonEdit(ref.read(taxonomyProvider), proposed);
                Navigator.pop(dialogContext, proposed);
              } catch (e) {
                update(() => error = '$e');
              }
            },
            child: const Text('Add option'),
          ),
        ],
      ),
    ),
  );
  if (result == null || !context.mounted) return null;
  if ((await ref.read(placeProvider.future)).id != place.id) {
    throw StateError('Orchard changed; add the option again');
  }
  if (!context.mounted) return null;
  validateTaxonEdit(ref.read(taxonomyProvider), result);
  ref.read(orchardRepositoryProvider).saveTaxon(place.id, result);
  ref.read(submittedTaxaProvider.notifier).state = {
    ...ref.read(submittedTaxaProvider),
    result.id: result,
  };
  return result;
}
