import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/models.dart';
import '../domain/work.dart';
import '../domain/task_edits.dart';
import '../domain/task_definition_changes.dart';
import '../domain/extensions.dart';
import 'task_schedule_fields.dart';
import 'task_target_editor.dart';
import 'orchard_theme.dart';
import 'common.dart';

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, this.task, this.plan, this.legacyGroup = false});
  final OrchardTask? task;
  final TaskPlan? plan;
  final bool legacyGroup;
  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final title = TextEditingController(
        text: widget.plan?.title ?? widget.task!.title,
      ),
      notes = TextEditingController(
        text: widget.plan?.notes ?? widget.task!.notes,
      ),
      quantity = TextEditingController(
        text: (widget.plan?.eventHarvest ?? widget.task?.eventHarvest)?.quantity
            .toString(),
      );
  TaskPlan? initial;
  String? due, end, mode, taxon;
  ActivityType? eventType;
  HarvestUnit unit = HarvestUnit.kg;
  Set<String> included = {}, excluded = {};
  List<int> offsets = [];
  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> save({bool deleting = false}) async {
    if (busy || initial == null) {
      return;
    }
    if (!ref.read(canEditOrchardProvider)) {
      setState(() => error = 'This orchard is read-only.');
      return;
    }
    if (deleting) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete entire task?'),
          content: const Text(
            'Remove this task and stop all future repeats? Open entries and reminders will be removed. Completed history and recorded plant activities will be retained. Other tasks and plants are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep task'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete entire task'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) {
        return;
      }
    }
    setState(() => busy = true);
    try {
      final orchard = await ref.read(placeProvider.future);
      if (orchard.id != initial!.propertyId) {
        throw StateError('Orchard changed. Reopen this task.');
      }
      final tasks = (await ref.read(tasksProvider.future)).value;
      final plans = await ref.read(taskPlansProvider.future);
      final latest =
          plans.where((p) => p.id == initial!.id).firstOrNull ?? initial!;
      if (latest.deleted) {
        throw StateError('This task has already been deleted.');
      }
      final now = DateTime.now();
      final harvest = deleting ? latest.eventHarvest : eventType == ActivityType.harvest
          ? Harvest(double.parse(quantity.text), unit) : null;
      if (!deleting) {
        requiredText(title.text, 'Task title');
        validateTaskDates(due, end);
        if (latest.repeat != RepeatSchedule.none && due == null) {
          throw StateError('Choose a start date for the repeating task');
        }
        if (offsets.isNotEmpty &&
            (due == null ||
                !await ref
                    .read(reminderSchedulerProvider)
                    .requestPermission())) {
          throw StateError(
            'Set a start date and enable notifications for reminders.',
          );
        }
      }
      final edited = deleting
          ? deletedTaskPlan(latest)
          : editPlan(
              latest,
              title: title.text,
              notes: notes.text,
              dueDate: due,
              endDate: end,
              eventType: eventType,
              eventHarvest: harvest,
              target: mode,
              taxonId: taxon,
              updateTargets: true,
              includedTargets: included.toList(),
              excludedTargets: excluded.toList(),
              now: now,
            );
      final plants = (await ref.read(plantsProvider.future)).value,
          crops = (await ref.read(cropsProvider.future)).value,
          sections = (await ref.read(sectionsProvider.future)).value;
      final changes = taskDefinitionChanges(
        old: latest,
        edited: edited,
        existing: tasks,
        plants: plants,
        crops: crops,
        sections: sections,
        taxonomy: ref.read(taxonomyProvider),
        now: now,
      );
      await ref
          .read(orchardRepositoryProvider)
          .saveTaskDefinition(edited, changes);
      final records = ref.read(orchardRecordsProvider);
      if (deleting || offsets.isEmpty) {
        await records.removeRecord(orchard.id, RecordKind.reminder, edited.id);
      } else {
        await records.putRecord(orchard.id, RecordKind.reminder, edited.id, {
          'offsets': offsets,
        });
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider),
        plans = ref.watch(taskPlansProvider),
        reminders = ref.watch(recordsProvider(RecordKind.reminder));
    if (initial == null &&
        tasks.hasValue &&
        plans.hasValue &&
        reminders.hasValue) {
      initial =
          plans.value!.where((p) => p.id == widget.plan?.id).firstOrNull ??
          widget.plan ??
          planForTask(widget.task!, plans.value!) ??
          planForLegacyTask(widget.task!, tasks.value!.value);
      final p = initial!;
      title.text = p.title;
      notes.text = p.notes;
      quantity.text = p.eventHarvest?.quantity.toString() ?? '';
      due =
          p.dueDate ??
          (p.repeat == RepeatSchedule.none
              ? null
              : calendarDate(p.createdAt.toLocal()));
      end = p.endDate;
      mode = p.target;
      taxon = p.taxonId;
      eventType = p.eventType;
      unit = p.eventHarvest?.unit ?? HarvestUnit.kg;
      included = p.includedTargets.toSet();
      excluded = p.excludedTargets.toSet();
      offsets = reminderOffsets(
        reminders.value!.where((r) => r['id'] == p.id).firstOrNull,
      );
    }
    final p = initial;
    final editable = ref.watch(canEditOrchardProvider);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit task')),
        body: tasks.hasError
            ? ErrorPanel(tasks.error!)
            : plans.hasError
            ? ErrorPanel(plans.error!)
            : reminders.hasError
            ? ErrorPanel(reminders.error!)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit task & reminders')),
      body: OrchardForm(
        title: 'Task & reminders',
        subtitle: 'Edit dates, matching plants and individual selections.',
        icon: Icons.checklist,
        children: [
          const Text(
            'Changes apply to open work in the current occurrence and to future repeats. Completed history and plant activities are retained.',
          ),
          TextField(
            controller: title,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Task title'),
          ),
          TextField(
            controller: notes,
            maxLength: 10000,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Task notes'),
          ),
          TaskTargetEditor(
            plan: p,
            mode: mode!,
            taxonId: taxon,
            included: included,
            excluded: excluded,
            onChanged: (m, t, i, e) {
              if (i.length > 400 || e.length > 400) {
                setState(
                  () => error = 'Use criteria for larger groups; at most 400 individual overrides are supported.',
                );
                return;
              }
              setState(() {
                mode = m;
                taxon = t;
                included = i;
                excluded = e;
                error = null;
              });
            },
          ),
          TaskScheduleFields(
            start: due,
            end: end,
            offsets: offsets,
            onDates: (s, e) => setState(() {
              due = s;
              end = e;
            }),
            onReminders: (v) => setState(() => offsets = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: eventType?.name ?? '',
            decoration: const InputDecoration(
              labelText: 'Activity on completion',
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('No activity')),
              for (final a in ActivityType.values.where(
                (a) => a != ActivityType.photo,
              ))
                DropdownMenuItem(value: a.name, child: Text(a.name)),
            ],
            onChanged: (s) => setState(
              () => eventType = s == '' ? null : ActivityType.values.byName(s!),
            ),
          ),
          if (eventType == ActivityType.harvest) ...[
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Harvest quantity'),
            ),
            DropdownButtonFormField<HarvestUnit>(
              initialValue: unit,
              items: [
                for (final u in HarvestUnit.values)
                  DropdownMenuItem(value: u, child: Text(u.name)),
              ],
              onChanged: (v) => unit = v!,
            ),
          ],
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy || !editable ? null : () => save(),
            child: Text(busy ? 'Saving…' : 'Save task changes'),
          ),
          OutlinedButton.icon(
            onPressed: busy || !editable ? null : () => save(deleting: true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete entire task'),
          ),
        ],
      ),
    );
  }
}
