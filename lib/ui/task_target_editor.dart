import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/work.dart';
import '../domain/landscape.dart';
import 'classification_picker.dart';

class TaskTargetEditor extends ConsumerStatefulWidget {
  const TaskTargetEditor({
    super.key,
    required this.plan,
    required this.mode,
    required this.taxonId,
    required this.included,
    required this.excluded,
    required this.onChanged,
  });
  final TaskPlan plan;
  final String mode;
  final String? taxonId;
  final Set<String> included, excluded;
  final void Function(String, String?, Set<String>, Set<String>) onChanged;
  @override
  ConsumerState<TaskTargetEditor> createState() => _TaskTargetState();
}

class _TaskTargetState extends ConsumerState<TaskTargetEditor> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final plants =
        ref.watch(plantsProvider).asData?.value.value ?? <ManagedPlant>[];
    final crops =
        ref.watch(cropsProvider).asData?.value.value ?? <CropPlanting>[];
    final sections =
        ref.watch(sectionsProvider).asData?.value.value ?? <OrchardSection>[];
    final taxonomy = ref.watch(taxonomyProvider);
    final p = widget.plan;
    final preview = TaskPlan(
      id: p.id,
      propertyId: p.propertyId,
      title: p.title,
      createdAt: p.createdAt,
      target: widget.mode,
      itemId: p.itemId,
      sectionId: widget.mode == p.target || widget.mode == 'section'
          ? p.sectionId
          : null,
      cropId: p.cropId,
      taxonId: widget.taxonId,
      sectionKind: p.sectionKind,
      includedTargets: widget.included.toList(),
      excludedTargets: widget.excluded.toList(),
    );
    final auto = matchingTaskTargets(
      preview,
      plants: plants,
      sections: sections,
      crops: crops,
      taxonomy: taxonomy,
      overrides: false,
    );
    final matches = matchingTaskTargets(
      preview,
      plants: plants,
      sections: sections,
      crops: crops,
      taxonomy: taxonomy,
    );
    final entries = <({String key, String name})>[
      for (final v in plants.where(
        (v) => v.propertyId == p.propertyId && v.status == ItemStatus.active,
      ))
        (key: 'p:${v.id}', name: v.name),
      for (final v in crops.where(
        (v) => v.propertyId == p.propertyId && v.status == CropStatus.growing,
      ))
        (key: 'c:${v.id}', name: '${v.label} · seasonal planting'),
      for (final v in sections.where(
        (s) =>
            s.propertyId == p.propertyId &&
            (widget.included.contains('s:${s.id}') ||
                auto.contains('s:${s.id}')),
      ))
        (key: 's:${v.id}', name: '${v.name} · ${v.kind.name}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('task-target-mode-${widget.mode}'),
          initialValue: widget.mode,
          decoration: const InputDecoration(labelText: 'Task targets'),
          items: [
            const DropdownMenuItem(
              value: 'property',
              child: Text('Whole orchard'),
            ),
            const DropdownMenuItem(
              value: 'plants',
              child: Text('Group / Type / Variety'),
            ),
            const DropdownMenuItem(
              value: 'manual',
              child: Text('Choose individual plants'),
            ),
            if (!['property', 'plants', 'manual'].contains(p.target))
              DropdownMenuItem(
                value: p.target,
                child: const Text('Keep current target scope'),
              ),
          ],
          onChanged: (v) {
            final include = v == 'manual'
                ? matches.where((k) => k != 'property').toSet()
                : <String>{};
            widget.onChanged(v!, widget.taxonId, include, {});
          },
        ),
        if (widget.mode == 'plants' || widget.mode == 'crops')
          ClassificationPicker(
            value: widget.taxonId,
            allowAny: true,
            allowCreate: false,
            onChanged: (id) => widget.onChanged(
              widget.mode,
              id,
              widget.included,
              widget.excluded,
            ),
          ),
        if (widget.mode != 'property') ...[
          const Text(
            'Matching plants join automatically. Individual selections override the criteria for this and future occurrences. Completed history is retained.',
          ),
          Text('${matches.length} selected targets'),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Find plants to add or remove',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          SizedBox(
            height: 220,
            child: ListView(
              children: [
                for (final e in entries.where(
                  (e) => e.name.toLowerCase().contains(query.toLowerCase()),
                ))
                  CheckboxListTile(
                    key: ValueKey('task-target-${e.key}'),
                    title: Text(e.name),
                    value: matches.contains(e.key),
                    subtitle: Text(
                      widget.excluded.contains(e.key)
                          ? 'Excluded from this task'
                          : widget.included.contains(e.key)
                          ? 'Always included'
                          : auto.contains(e.key)
                          ? 'Matches criteria'
                          : 'Not included',
                    ),
                    onChanged: (selected) {
                      final include = {...widget.included},
                          exclude = {...widget.excluded};
                      if (selected == true) {
                        exclude.remove(e.key);
                        if (!auto.contains(e.key)) {
                          include.add(e.key);
                        }
                      } else {
                        include.remove(e.key);
                        exclude.add(e.key);
                      }
                      widget.onChanged(
                        widget.mode,
                        widget.taxonId,
                        include,
                        exclude,
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
