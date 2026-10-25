import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/taxonomy.dart';
import 'icon_library_screen.dart';
import 'icon_picker.dart';
import 'version_history_screen.dart';
import 'foraging_screen.dart';
import 'sharing_screen.dart';
import 'reports_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.people),
          title: const Text('Orchard sharing'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SharingScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.eco),
          title: const Text('Foraging resources'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ForagingScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Harvest reports & recovery'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Version History'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const VersionHistoryScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Group, Type & Variety options'),
          subtitle: const Text('Edit classification names and map icons'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ClassificationSettingsScreen(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.collections_outlined),
          title: const Text('Custom icons'),
          subtitle: const Text('Import images for this orchard'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const IconLibraryScreen()),
          ),
        ),
      ],
    ),
  );
}

String classificationRank(TaxonRank rank) => switch (rank) {
  TaxonRank.group => 'Group',
  TaxonRank.genus => 'Type',
  _ => 'Variety',
};

class ClassificationSettingsScreen extends ConsumerStatefulWidget {
  const ClassificationSettingsScreen({super.key});
  @override
  ConsumerState<ClassificationSettingsScreen> createState() =>
      _ClassificationSettingsState();
}

class _ClassificationSettingsState
    extends ConsumerState<ClassificationSettingsScreen> {
  String query = '';
  String? message;
  Future<void> edit(Taxon taxon) async {
    final orchard = await ref.read(placeProvider.future);
    if (!mounted) return;
    final updated = await showDialog<Taxon>(
      context: context,
      builder: (_) => _TaxonEditor(taxon),
    );
    if (updated == null || !mounted) return;
    try {
      if ((await ref.read(placeProvider.future)).id != orchard.id) {
        throw StateError('Orchard changed; edit again');
      }
      validateTaxonEdit(ref.read(taxonomyProvider), updated);
      ref.read(orchardRepositoryProvider).saveTaxon(orchard.id, updated);
      ref.read(submittedTaxaProvider.notifier).state = {
        ...ref.read(submittedTaxaProvider),
        updated.id: updated,
      };
      setState(() => message = 'Option saved');
    } catch (e) {
      if (mounted) setState(() => message = 'Could not save option: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = ref.watch(taxonomyProvider);
    final options =
        taxonomy.taxa
            .where(
              (t) => '${t.name} ${classificationRank(t.rank)}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => taxonomy
                .ancestry(a.id)
                .map((t) => t.name)
                .join('/')
                .compareTo(
                  taxonomy.ancestry(b.id).map((t) => t.name).join('/'),
                ),
          );
    final state = ref.watch(customTaxaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Classification options')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Changes apply to plants using this option in the selected orchard.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Find Group, Type or Variety',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          if (state.hasError)
            const Text(
              'Could not load saved options. Try again when orchard data is available.',
            ),
          if (message != null) Text(message!),
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (_, index) {
                final taxon = options[index];
                return ListTile(
                  leading: IconPreview(
                    symbol: taxonomy.iconFor(taxon.id).symbol,
                    customIconId: taxonomy.iconFor(taxon.id).customIconId,
                  ),
                  title: Text(taxon.name),
                  subtitle: Text(
                    '${classificationRank(taxon.rank)} · ${taxonomy.ancestry(taxon.id).map((t) => t.name).join(' / ')}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: state.hasValue ? () => edit(taxon) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxonEditor extends ConsumerStatefulWidget {
  const _TaxonEditor(this.taxon);
  final Taxon taxon;
  @override
  ConsumerState<_TaxonEditor> createState() => _TaxonEditorState();
}

class _TaxonEditorState extends ConsumerState<_TaxonEditor> {
  late final name = TextEditingController(text: widget.taxon.name);
  late PlantSymbol symbol;
  late String? customIconId;
  bool iconChanged = false, inheritIcon = false;
  @override
  void initState() {
    super.initState();
    final appearance = ref.read(taxonomyProvider).iconFor(widget.taxon.id);
    symbol = appearance.symbol;
    customIconId = appearance.customIconId;
  }

  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${classificationRank(widget.taxon.rank)}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Option name',
              errorText: error,
            ),
          ),
          MapIconPicker(
            symbol: symbol,
            customIconId: customIconId,
            onChanged: (s, id) => setState(() {
              symbol = s!;
              customIconId = id;
              iconChanged = true;
              inheritIcon = false;
            }),
          ),
          if (widget.taxon.parentId != null)
            TextButton(
              onPressed: () => setState(() {
                final parent = ref
                    .read(taxonomyProvider)
                    .iconFor(widget.taxon.parentId!);
                symbol = parent.symbol;
                customIconId = parent.customIconId;
                iconChanged = true;
                inheritIcon = true;
              }),
              child: const Text('Use parent icon'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final updated = Taxon(
              id: widget.taxon.id,
              name: requiredText(name.text, 'Option name'),
              rank: widget.taxon.rank,
              parentId: widget.taxon.parentId,
              scientificName: widget.taxon.scientificName,
              symbol: iconChanged ? symbol : widget.taxon.symbol,
              customIconId: iconChanged
                  ? customIconId
                  : widget.taxon.customIconId,
              iconOverride: iconChanged
                  ? !inheritIcon
                  : widget.taxon.iconOverride,
            );
            validateTaxonEdit(ref.read(taxonomyProvider), updated);
            Navigator.pop(context, updated);
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Save option'),
      ),
    ],
  );
}
