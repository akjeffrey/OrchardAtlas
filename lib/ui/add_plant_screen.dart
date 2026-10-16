import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/taxonomy.dart';
import 'plant_symbols.dart';

class AddPlantScreen extends ConsumerStatefulWidget {
  const AddPlantScreen({super.key, this.template, this.location});
  final PlantTemplate? template;
  final Coordinates? location;
  @override
  ConsumerState<AddPlantScreen> createState() => _AddPlantState();
}

class _AddPlantState extends ConsumerState<AddPlantScreen> {
  final name = TextEditingController();
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final selected = <String?>[null, null, null, null];
  bool customName = false, busy = false, locating = false;
  int locationRevision = 0;
  int dropdownRevision = 0;
  DateTime? plantingDate;
  bool templateApplied = false;
  String? message;
  @override
  void initState() {
    super.initState();
    applyTemplate(ref.read(taxonomyProvider));
    if (widget.location != null) {
      setCoordinates(widget.location!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) locate();
      });
    }
  }

  void applyTemplate(Taxonomy taxonomy) {
    final template = widget.template;
    if (template == null ||
        templateApplied ||
        !taxonomy.taxa.any((t) => t.id == template.taxonId)) {
      return;
    }
    final path = taxonomy.ancestry(template.taxonId);
    name.text = template.name;
    customName = template.name != path.last.name;
    for (var i = 0; i < path.length; i++) {
      selected[i] = path[i].id;
    }
    templateApplied = true;
  }

  void setCoordinates(Coordinates p) {
    latitude.text = p.latitude.toStringAsFixed(7);
    longitude.text = p.longitude.toStringAsFixed(7);
  }

  void choose(int rank, String? id) {
    setState(() {
      selected[rank] = id;
      for (var j = rank + 1; j < 4; j++) {
        selected[j] = null;
      }
      if (!customName || name.text.trim().isEmpty) {
        customName = false;
        final last = selected.whereType<String>().lastOrNull;
        name.text = last == null
            ? ''
            : ref.read(taxonomyProvider).byId(last).name;
      }
    });
  }

  @override
  void dispose() {
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    if (locating) return;
    final revision = locationRevision;
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted || revision != locationRevision) return;
      setState(() {
        setCoordinates(fix.coordinates);
        message =
            'GPS accuracy ±${fix.accuracyMeters.round()} m. Adjust coordinates if needed.';
      });
    } catch (_) {
      if (mounted && revision == locationRevision) {
        setState(
          () => message = 'GPS unavailable. Enable location access or enter coordinates below.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> addOption(int rank) async {
    final parent = rank == 0 ? null : selected[rank - 1];
    var optionName = '';
    var symbol = parent == null
        ? PlantSymbol.tree
        : ref.read(taxonomyProvider).byId(parent).symbol;
    String? error;
    final result = await showDialog<Taxon>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Add ${TaxonRank.values[rank].name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => optionName = value,
                  autofocus: true,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: 'Option name',
                    errorText: error,
                  ),
                ),
                DropdownButtonFormField<PlantSymbol>(
                  initialValue: symbol,
                  decoration: const InputDecoration(labelText: 'Map icon'),
                  items: [
                    for (final s in PlantSymbol.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text('${symbolLabels[s]} ${s.name}'),
                      ),
                  ],
                  onChanged: (s) => symbol = s!,
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
                final value = optionName.trim();
                if (value.isEmpty) {
                  update(() => error = 'Enter a name');
                  return;
                }
                if (ref
                    .read(taxonomyProvider)
                    .children(parent)
                    .any((t) => t.name.toLowerCase() == value.toLowerCase())) {
                  update(() => error = 'This option already exists');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  Taxon(
                    id: const Uuid().v4(),
                    name: value,
                    rank: TaxonRank.values[rank],
                    parentId: parent,
                    symbol: symbol,
                  ),
                );
              },
              child: const Text('Add option'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => dropdownRevision++);
    if (result == null || !mounted) return;
    try {
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      Taxonomy([...ref.read(taxonomyProvider).taxa, result]);
      ref.read(orchardRepositoryProvider).saveTaxon(place.id, result);
      ref.read(submittedTaxaProvider.notifier).state = {
        ...ref.read(submittedTaxaProvider),
        result.id: result,
      };
      choose(rank, result.id);
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add option: $e');
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final taxonId = selected[3] ?? selected[2];
      if (taxonId == null) {
        throw ArgumentError('Select group, genus and species');
      }
      final position = Coordinates(
        double.parse(latitude.text),
        double.parse(longitude.text),
      );
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final plant = ref
          .read(commandsProvider)
          .addPlant(
            place: place,
            name: name.text,
            taxonId: taxonId,
            location: position,
            plantingDate: plantingDate,
            authorId: ref.read(userProvider).valueOrNull?.id,
          );
      final another = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Plant added'),
          content: Text('${plant.name} added. Add another like this?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back to map'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add another'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (another == true) {
        setState(() {
          latitude.clear();
          longitude.clear();
          plantingDate = null;
          locationRevision++;
          message = null;
        });
        await locate();
      } else {
        context.go('/', extra: plant.location);
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider);
    final catalog = ref.watch(customTaxaProvider);
    applyTemplate(taxonomy);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.template == null ? 'Add Plant' : 'Add Another Like This',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.template != null)
            const Text(
              'Name and taxonomy copied. Fetching a fresh position for this plant.',
            ),
          TextField(
            controller: name,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Plant name',
              helperText: 'Defaults to your latest taxonomy choice',
            ),
            onChanged: (value) => customName = value.trim().isNotEmpty,
          ),
          if (catalog.hasError)
            const Text(
              'Saved taxonomy could not be loaded. Reconnect and retry before adding custom options.',
            ),
          for (var i = 0; i < 4; i++)
            if (i == 0 || selected[i - 1] != null)
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'taxon-$dropdownRevision-$i-${selected[i]}-${i == 0 ? "" : selected[i - 1]}',
                ),
                initialValue: selected[i],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: [
                    'Group',
                    'Genus',
                    'Species',
                    'Cultivar (optional)',
                  ][i],
                ),
                items: [
                  if (i == 3)
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Unspecified cultivar'),
                    ),
                  for (final t in taxonomy.children(
                    i == 0 ? null : selected[i - 1],
                  ))
                    DropdownMenuItem(
                      value: t.id,
                      child: Text('${symbolLabels[t.symbol]} ${t.name}'),
                    ),
                  const DropdownMenuItem(
                    value: '__add__',
                    child: Text('+ Add new option…'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value == '__add__') {
                          addOption(i);
                        } else {
                          choose(i, value == '' ? null : value);
                        }
                      },
              ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: const Text('Planting date (optional)'),
            subtitle: Text(
              plantingDate == null
                  ? 'Not recorded'
                  : calendarDate(plantingDate!),
            ),
            onTap: busy
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: plantingDate ?? DateTime.now(),
                      firstDate: DateTime(1800),
                      lastDate: DateTime.now(),
                    );
                    if (date != null && mounted) {
                      setState(() => plantingDate = date);
                    }
                  },
            trailing: plantingDate == null
                ? null
                : IconButton(
                    tooltip: 'Clear planting date',
                    icon: const Icon(Icons.clear),
                    onPressed: busy
                        ? null
                        : () => setState(() => plantingDate = null),
                  ),
          ),
          OutlinedButton.icon(
            onPressed: locating || busy ? null : locate,
            icon: const Icon(Icons.my_location),
            label: Text(locating ? 'Locating…' : 'Use current GPS location'),
          ),
          TextButton(
            onPressed: () =>
                ref.read(locationRepositoryProvider).openSettings(),
            child: const Text('Open location settings'),
          ),
          TextField(
            controller: latitude,
            decoration: const InputDecoration(
              labelText: 'Latitude (−90 to 90)',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (_) => locationRevision++,
          ),
          TextField(
            controller: longitude,
            decoration: const InputDecoration(
              labelText: 'Longitude (−180 to 180)',
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onChanged: (_) => locationRevision++,
          ),
          if (message != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
          FilledButton(
            onPressed: busy || locating ? null : save,
            child: Text(busy ? 'Saving…' : 'Save plant locally'),
          ),
        ],
      ),
    );
  }
}
