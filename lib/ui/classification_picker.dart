import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'taxon_creation_dialog.dart';

class ClassificationPicker extends ConsumerStatefulWidget {
  const ClassificationPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAny = false,
    this.allowCreate = true,
  });
  final bool allowAny, allowCreate;
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  ConsumerState<ClassificationPicker> createState() =>
      _ClassificationPickerState();
}

class _ClassificationPickerState extends ConsumerState<ClassificationPicker> {
  int revision = 0;
  bool busy = false;
  String? error;
  Future<void> create(int rank, String? parentId) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final option = await createTaxonOption(
        context,
        ref,
        rank: rank,
        parentId: parentId,
      );
      if (option != null && mounted) widget.onChanged(option.id);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not add option: $e');
    } finally {
      if (mounted) {
        setState(() {
          revision++;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final taxonomy = ref.watch(taxonomyProvider);
    final path = value != null && taxonomy.taxa.any((t) => t.id == value)
        ? taxonomy.ancestry(value)
        : <Taxon>[];
    final group = path.firstOrNull?.id,
        type = path.length > 1 ? path[1].id : null;
    return Column(
      spacing: 12,
      children: [
        if (error != null) Text(error!),
        for (var level = 0; level < 3; level++)
          if (level == 0 ||
              level == 1 && group != null ||
              level == 2 && type != null)
            DropdownButtonFormField<String>(
              key: ValueKey('classification-$revision-$level-$value'),
              isExpanded: true,
              initialValue:
                  (level == 0
                      ? group
                      : level == 1
                      ? type
                      : (path.length >= 3 ? value : null)) ??
                  (widget.allowAny ? '' : null),
              decoration: InputDecoration(
                labelText: ['Group', 'Type', 'Variety'][level],
              ),
              items: [
                if (widget.allowAny)
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      ['All groups', 'All types', 'All varieties'][level],
                    ),
                  ),
                for (final t
                    in level == 2
                        ? taxonomy.taxa.where(
                            (t) =>
                                t.rank.index >= 2 &&
                                taxonomy
                                    .ancestry(t.id)
                                    .any((a) => a.id == type),
                          )
                        : taxonomy.children(level == 0 ? null : group))
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(t.name, overflow: TextOverflow.ellipsis),
                  ),
                if (widget.allowCreate)
                  const DropdownMenuItem(
                    value: '__add__',
                    child: Text('+ Add new option…'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (id) {
                      if (id == '__add__') {
                        create(
                          level,
                          level == 0
                              ? null
                              : level == 1
                              ? group
                              : type,
                        );
                      } else {
                        widget.onChanged(
                          id == ''
                              ? (level == 0
                                    ? null
                                    : level == 1
                                    ? group
                                    : type)
                              : id,
                        );
                      }
                    },
            ),
      ],
    );
  }
}
