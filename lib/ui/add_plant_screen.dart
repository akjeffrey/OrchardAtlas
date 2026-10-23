import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/taxonomy.dart';
import '../domain/work.dart';
import '../domain/landscape.dart';
import 'icon_picker.dart';
import 'plant_location_picker.dart';
import 'taxon_creation_dialog.dart';
import 'sections_screen.dart';

class AddPlantScreen extends ConsumerStatefulWidget {
  const AddPlantScreen({
    super.key,
    this.template,
    this.location,
    this.sectionId,
  });
  final PlantTemplate? template;
  final String? sectionId;
  final Coordinates? location;
  @override
  ConsumerState<AddPlantScreen> createState() => _AddPlantState();
}

class _AddPlantState extends ConsumerState<AddPlantScreen> {
  final name = TextEditingController();
  final rootstock = TextEditingController();
  final nursery = TextEditingController();
  final season = TextEditingController();
  final notes = TextEditingController();
  double? accuracyMeters;
  String? sectionId;
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final selected = <String?>[null, null, null, null];
  bool customName = false, busy = false, locating = false;
  int locationRevision = 0;
  int dropdownRevision = 0;
  DateTime? plantingDate = DateTime.now();
  bool templateApplied = false;
  String? message;
  @override
  void initState() {
    super.initState();
    sectionId = widget.sectionId;
    applyTemplate(ref.read(taxonomyProvider));
    final initialLocation = widget.location ?? widget.template?.location;
    if (initialLocation != null) {
      setCoordinates(initialLocation);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (sectionId != null) {
            useSection(sectionId);
          } else {
            locate();
          }
        }
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
    plantingDate = template.plantedOn == null
        ? null
        : parseCalendarDate(template.plantedOn!);
    sectionId = template.sectionId;
    rootstock.text = template.rootstock;
    season.text = template.season ?? '${DateTime.now().year}';
    nursery.text = template.nursery;
    customName = template.name != path.last.name;
    for (var i = 0; i < path.length; i++) {
      selected[i] = path[i].id;
    }
    if (path.length == 4) selected[2] = path.last.id;
    templateApplied = true;
  }

  Future<void> useSection(String? id) async {
    final revision = ++locationRevision;
    setState(() {
      sectionId = id;
      locating = false;
    });
    if (id == null) return;
    final sections = await ref.read(sectionsProvider.future);
    if (!mounted || revision != locationRevision) return;
    final section = sections.value.where((s) => s.id == id).firstOrNull;
    if (section != null) {
      setState(() {
        setCoordinates(
          section.kind == SectionKind.row
              ? section.vertices.first
              : sectionCenter(section),
        );
        accuracyMeters = null;
        message = 'Using ${section.name} location';
      });
    }
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
    rootstock.dispose();
    nursery.dispose();
    season.dispose();
    notes.dispose();
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    if (locating) return;
    final revision = ++locationRevision;
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationRepositoryProvider).currentPosition();
      if (!mounted || revision != locationRevision) return;
      setState(() {
        setCoordinates(fix.coordinates);
        accuracyMeters = fix.accuracyMeters;
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
      if (mounted && revision == locationRevision) {
        setState(() => locating = false);
      }
    }
  }

  Future<void> pickLocation() async {
    // Invalidate any in-flight GPS/section lookup before opening the picker.
    locationRevision++;
    setState(() => locating = false);
    Coordinates initial =
        widget.location ??
        widget.template?.location ??
        ref.read(plantsProvider).valueOrNull?.value.firstOrNull?.location ??
        Coordinates(0, 0);
    try {
      initial = Coordinates(
        double.parse(latitude.text),
        double.parse(longitude.text),
      );
    } on ArgumentError {
      // Invalid manual input must not block the map picker.
    } on FormatException {
      // Start with a known location until the user chooses a point.
    }
    final location = await Navigator.of(context).push<Coordinates>(
      MaterialPageRoute(
        builder: (_) => PlantLocationPicker(initialLocation: initial),
      ),
    );
    if (!mounted || location == null) return;
    setState(() {
      setCoordinates(location);
      accuracyMeters = null;
      message = 'Using location selected on map';
    });
  }

  Future<void> addOption(int rank) async {
    try {
      final result = await createTaxonOption(
        context,
        ref,
        rank: rank,
        parentId: rank == 0 ? null : selected[rank - 1],
      );
      if (result != null && mounted) choose(rank, result.id);
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add option: $e');
    } finally {
      if (mounted) setState(() => dropdownRevision++);
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
        throw ArgumentError('Select Group, Type and Variety');
      }
      final position = Coordinates(
        double.parse(latitude.text),
        double.parse(longitude.text),
      );
      final place = await ref.read(placeProvider.future);
      final user = await ref.read(userProvider.future);
      if (!mounted) return;
      if (user == null) throw StateError('Please sign in again');
      final plant = ref
          .read(commandsProvider)
          .addPlant(
            place: place,
            name: name.text,
            taxonId: taxonId,
            location: position,
            plantingDate: plantingDate,
            sectionId: sectionId,
            rootstock: rootstock.text,
            lifeCycle: widget.template?.lifeCycle ?? PlantLifeCycle.perennial,
            season: widget.template?.lifeCycle == PlantLifeCycle.annual
                ? season.text.trim()
                : widget.template?.season,
            nursery: nursery.text,
            notes: notes.text,
            accuracyMeters: accuracyMeters,
            authorId: user.id,
            rowOrder: sectionId == null
                ? null
                : (ref
                          .read(plantsProvider)
                          .valueOrNull
                          ?.value
                          .where((p) => p.sectionId == sectionId)
                          .fold<double>(
                            0,
                            (n, p) => p.rowOrder != null && p.rowOrder! >= n
                                ? p.rowOrder! + 1
                                : n + 1,
                          ) ??
                      0),
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
          setCoordinates(plant.location);
          notes.clear();
          accuracyMeters = null;
          locationRevision++;
          message = null;
        });
        // A repeated entry starts at the plant just saved; GPS is opt-in.
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
              'Name, taxonomy, planting date, rootstock, source and location copied. Choose a different spot if needed.',
            ),
          TextField(
            key: const ValueKey('plant-name'),
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
          for (var i = 0; i < 3; i++)
            if (i == 0 || selected[i - 1] != null)
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'taxon-$dropdownRevision-$i-${selected[i]}-${i == 0 ? "" : selected[i - 1]}',
                ),
                initialValue: selected[i],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: ['Group', 'Type', 'Variety'][i],
                ),
                items: [
                  if (i == 3)
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Unspecified cultivar'),
                    ),
                  for (final t
                      in i == 2
                          ? taxonomy.taxa.where(
                              (t) =>
                                  t.rank.index >= 2 &&
                                  taxonomy
                                      .ancestry(t.id)
                                      .any((a) => a.id == selected[1]),
                            )
                          : taxonomy.children(i == 0 ? null : selected[i - 1]))
                    DropdownMenuItem(
                      value: t.id,
                      child: TaxonOptionLabel(taxon: t),
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
          SectionPicker(value: sectionId, onChanged: (id) => useSection(id)),
          if (widget.template?.lifeCycle == PlantLifeCycle.annual)
            TextField(
              controller: season,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Season / year'),
            ),
          TextField(
            controller: rootstock,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Rootstock (optional)',
            ),
          ),
          TextField(
            controller: nursery,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Nursery / source (optional)',
            ),
          ),
          TextField(
            controller: notes,
            maxLength: 10000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Plant notes (optional)',
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : pickLocation,
            icon: const Icon(Icons.edit_location_alt),
            label: const Text('Pick location on map'),
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
            onChanged: (_) => setState(() {
              locationRevision++;
              locating = false;
              accuracyMeters = null;
            }),
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
            onChanged: (_) => setState(() {
              locationRevision++;
              locating = false;
              accuracyMeters = null;
            }),
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
