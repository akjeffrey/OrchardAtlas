import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';

class ClassificationPicker extends ConsumerWidget {
  const ClassificationPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxonomy = ref.watch(taxonomyProvider);
    final path = value != null && taxonomy.taxa.any((t) => t.id == value)
        ? taxonomy.ancestry(value!)
        : <Taxon>[];
    final group = path.firstOrNull?.id,
        type = path.length > 1 ? path[1].id : null;
    return Column(
      children: [
        for (var level = 0; level < 3; level++)
          if (level == 0 ||
              level == 1 && group != null ||
              level == 2 && type != null)
            DropdownButtonFormField<String>(
              key: ValueKey('classification-$level-$value'),
              isExpanded: true,
              initialValue: level == 0
                  ? group
                  : level == 1
                  ? type
                  : (path.length >= 3 ? value : null),
              decoration: InputDecoration(
                labelText: ['Group', 'Type', 'Variety'][level],
              ),
              items: [
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
              ],
              onChanged: onChanged,
            ),
      ],
    );
  }
}
