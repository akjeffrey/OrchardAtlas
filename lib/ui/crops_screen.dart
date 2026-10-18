import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';
import 'common.dart';
import 'sections_screen.dart';
import 'tasks_screen.dart';

class CropFormScreen extends ConsumerStatefulWidget {
  const CropFormScreen({super.key, this.section, this.source});
  final OrchardSection? section;
  final CropPlanting? source;
  @override
  ConsumerState<CropFormScreen> createState() => _CropFormState();
}

class _CropFormState extends ConsumerState<CropFormScreen> {
  final label = TextEditingController(),
      season = TextEditingController(text: '${DateTime.now().year}'),
      notes = TextEditingController();
  String? sectionId, taxonId, error;
  DateTime? date = DateTime.now();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    sectionId = widget.section?.id ?? widget.source?.sectionId;
    taxonId = widget.source?.taxonId;
    label.text = widget.source?.label ?? '';
  }

  @override
  void dispose() {
    label.dispose();
    season.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> variety() async {
    if (taxonId == null) return;
    final taxonomy = ref.read(taxonomyProvider);
    final type = taxonomy
        .ancestry(taxonId!)
        .firstWhere((t) => t.rank == TaxonRank.genus);
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${type.name} variety'),
        content: TextField(
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Variety name'),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Add variety'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      final value = requiredText(result, 'Variety');
      if (taxonomy.taxa
          .where((t) => taxonomy.descendants(type.id).contains(t.id))
          .any((t) => t.name.toLowerCase() == value.toLowerCase())) {
        throw ArgumentError('Variety already exists');
      }
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final taxon = Taxon(
        id: const Uuid().v4(),
        name: value,
        rank: TaxonRank.species,
        parentId: type.id,
        symbol: taxonomy.iconFor(type.id).symbol,
        customIconId: taxonomy.iconFor(type.id).customIconId,
        iconOverride: false,
      );
      ref.read(orchardRepositoryProvider).saveTaxon(place.id, taxon);
      ref.read(submittedTaxaProvider.notifier).state = {
        ...ref.read(submittedTaxaProvider),
        taxon.id: taxon,
      };
      setState(() {
        taxonId = taxon.id;
        label.text = value;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (sectionId == null || taxonId == null) {
        throw ArgumentError('Select a section and crop classification');
      }
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      final crop = CropPlanting(
        id: const Uuid().v4(),
        propertyId: place.id,
        sectionId: sectionId!,
        taxonId: taxonId!,
        label: label.text.trim().isEmpty
            ? ref.read(taxonomyProvider).byId(taxonId!).name
            : label.text,
        season: season.text,
        plantedOn: date == null ? null : calendarDate(date!),
        notes: notes.text,
        createdAt: DateTime.now().toUtc(),
      );
      ref.read(orchardRepositoryProvider).saveCrop(crop);
      context.go('/crops/${crop.id}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider);
    final identities = taxonomy.taxa
        .where((t) => t.rank.index >= TaxonRank.species.index)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.source == null
              ? 'Seasonal planting'
              : 'Replant for a new season',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.source != null)
            const Text(
              'Creates a separate planting. Earlier seasons and harvest records are retained.',
            ),
          SectionPicker(
            value: sectionId,
            onChanged: (id) => setState(() => sectionId = id),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('crop-taxon-$taxonId-${identities.length}'),
            initialValue: identities.any((t) => t.id == taxonId)
                ? taxonId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Crop Variety'),
            items: [
              for (final t in identities)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    taxonomy.ancestry(t.id).map((p) => p.name).join(' › '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(() {
              taxonId = id;
              if (label.text.isEmpty) label.text = taxonomy.byId(id!).name;
            }),
          ),
          TextButton(
            onPressed: taxonId == null || busy ? null : variety,
            child: const Text('Add a new variety'),
          ),
          TextField(
            controller: label,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Planting / row segment label',
              helperText: 'For example: German Extra Hardy · north half',
            ),
          ),
          TextField(
            controller: season,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Season / year',
              helperText: 'For example: 2026 autumn or 2027',
            ),
          ),
          ListTile(
            title: const Text('Planting date (optional)'),
            subtitle: Text(date == null ? 'Not recorded' : calendarDate(date!)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime.now(),
                firstDate: DateTime(1800),
                lastDate: DateTime(2100, 12, 31),
              );
              if (picked != null && mounted) setState(() => date = picked);
            },
            trailing: date == null
                ? null
                : IconButton(
                    tooltip: 'Clear planting date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => date = null),
                  ),
          ),
          TextField(
            controller: notes,
            maxLength: 10000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Planting notes'),
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save planting'),
          ),
        ],
      ),
    );
  }
}

class CropDetailScreen extends ConsumerWidget {
  const CropDetailScreen(this.id, {super.key});
  final String id;
  Future<void> finish(
    BuildContext context,
    WidgetRef ref,
    CropPlanting crop,
    CropStatus status,
  ) async {
    DateTime? date;
    if (status == CropStatus.harvested) {
      date = await showDatePicker(
        context: context,
        initialDate:
            DateTime.now().isBefore(
              parseCalendarDate(crop.plantedOn ?? '1800-01-01'),
            )
            ? parseCalendarDate(crop.plantedOn!)
            : DateTime.now(),
        firstDate: crop.plantedOn == null
            ? DateTime(1800)
            : parseCalendarDate(crop.plantedOn!),
        lastDate: DateTime(2100, 12, 31),
      );
      if (date == null || !context.mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End this season?'),
          content: const Text(
            'Keep this planting and harvest history. Replanting creates a new record.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End season'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      ref
          .read(orchardRepositoryProvider)
          .saveCrop(
            crop.finish(
              status,
              date: status == CropStatus.harvested ? calendarDate(date!) : null,
            ),
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Seasonal planting')),
    body: ref
        .watch(cropsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(e),
          data: (snapshot) {
            final c = snapshot.value.where((c) => c.id == id).firstOrNull;
            if (c == null) return const ErrorPanel('Planting unavailable');
            final section = ref
                .watch(sectionsProvider)
                .valueOrNull
                ?.value
                .where((s) => s.id == c.sectionId)
                .firstOrNull;
            final taxon = ref
                .watch(taxonomyProvider)
                .taxa
                .where((t) => t.id == c.taxonId)
                .firstOrNull;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  c.label,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  '${taxon?.name ?? 'Classification unavailable'} · ${c.season}',
                ),
                Text(
                  '${section?.name ?? 'Section unavailable'} · ${c.status.name}',
                ),
                Text('Planted: ${c.plantedOn ?? 'Not recorded'}'),
                if (c.harvestedOn != null)
                  Text('Harvest complete: ${c.harvestedOn}'),
                Text(c.notes),
                SyncStatus(snapshot),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => context.go('/sections/${c.sectionId}'),
                      child: const Text('View Area / Row'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/crops/new', extra: c),
                      child: const Text('Replant for a new season'),
                    ),
                    TextButton(
                      onPressed: () => context.push(
                        '/tasks/new',
                        extra: TaskTarget(cropId: id),
                      ),
                      child: const Text('Add crop task'),
                    ),
                    if (c.status == CropStatus.growing)
                      TextButton(
                        onPressed: () =>
                            finish(context, ref, c, CropStatus.harvested),
                        child: const Text('Mark harvest complete'),
                      ),
                    if (c.status != CropStatus.ended)
                      TextButton(
                        onPressed: () =>
                            finish(context, ref, c, CropStatus.ended),
                        child: const Text('End season'),
                      ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/crops/$id/harvest'),
                  icon: const Icon(Icons.agriculture),
                  label: const Text('Record crop harvest'),
                ),
                ref
                    .watch(cropHarvestsProvider)
                    .when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('$e'),
                      data: (data) {
                        final harvests =
                            data.value.where((h) => h.cropId == id).toList()
                              ..sort(
                                (a, b) =>
                                    b.activityDate.compareTo(a.activityDate),
                              );
                        final years =
                            harvests
                                .map(
                                  (h) => parseCalendarDate(h.activityDate).year,
                                )
                                .toSet()
                                .toList()
                              ..sort((a, b) => b.compareTo(a));
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SyncStatus(data),
                            if (harvests.isEmpty)
                              const Text('No harvest quantities recorded.'),
                            for (final year in years)
                              Text(
                                '$year: ${[for (final unit in HarvestUnit.values)
                                  if (harvests.any((h) => parseCalendarDate(h.activityDate).year == year && h.harvest.unit == unit)) '${harvests.where((h) => parseCalendarDate(h.activityDate).year == year && h.harvest.unit == unit).fold(0.0, (sum, h) => sum + h.harvest.quantity).toStringAsFixed(unit == HarvestUnit.count ? 0 : 3)} ${unit.name}'].join(' · ')}',
                              ),
                            for (final h in harvests)
                              ListTile(
                                title: Text(
                                  '${h.activityDate} · ${h.harvest.quantity} ${h.harvest.unit.name}',
                                ),
                                subtitle: Text(h.notes),
                              ),
                          ],
                        );
                      },
                    ),
              ],
            );
          },
        ),
  );
}

class CropHarvestScreen extends ConsumerStatefulWidget {
  const CropHarvestScreen(this.cropId, {super.key});
  final String cropId;
  @override
  ConsumerState<CropHarvestScreen> createState() => _HarvestState();
}

class _HarvestState extends ConsumerState<CropHarvestScreen> {
  final quantity = TextEditingController(), notes = TextEditingController();
  HarvestUnit unit = HarvestUnit.kg;
  DateTime date = DateTime.now();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    quantity.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final place = await ref.read(placeProvider.future);
      final crops = await ref.read(cropsProvider.future);
      final crop = crops.value.firstWhere((c) => c.id == widget.cropId);
      if (crop.plantedOn != null &&
          calendarDate(date).compareTo(crop.plantedOn!) < 0) {
        throw ArgumentError('Harvest date precedes planting');
      }
      if (!mounted) return;
      ref
          .read(orchardRepositoryProvider)
          .appendCropHarvest(
            CropHarvest(
              id: const Uuid().v4(),
              propertyId: place.id,
              cropId: widget.cropId,
              activityDate: calendarDate(date),
              harvest: Harvest(double.parse(quantity.text), unit),
              recordedAt: DateTime.now().toUtc(),
              notes: notes.text,
            ),
          );
      context.go('/crops/${widget.cropId}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record crop harvest')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Harvest quantity'),
        ),
        DropdownButtonFormField<HarvestUnit>(
          initialValue: unit,
          decoration: const InputDecoration(labelText: 'Unit'),
          items: [
            for (final u in HarvestUnit.values)
              DropdownMenuItem(value: u, child: Text(u.name)),
          ],
          onChanged: (u) => setState(() => unit = u!),
        ),
        ListTile(
          title: Text('Harvest date: ${calendarDate(date)}'),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(1800),
              lastDate: DateTime(2100, 12, 31),
            );
            if (picked != null && mounted) setState(() => date = picked);
          },
        ),
        TextField(
          controller: notes,
          maxLength: 10000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Harvest notes'),
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Save crop harvest'),
        ),
      ],
    ),
  );
}
