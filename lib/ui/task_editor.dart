import 'orchard_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/models.dart';
import '../domain/work.dart';
import '../domain/task_edits.dart';
import '../domain/extensions.dart';

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, this.task, this.plan});
  final OrchardTask? task;
  final TaskPlan? plan;
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
  late String? due = widget.plan?.dueDate ?? widget.task?.dueDate;
  late ActivityType? eventType =
      widget.plan?.eventType ?? widget.task?.eventType;
  late HarvestUnit unit =
      (widget.plan?.eventHarvest ?? widget.task?.eventHarvest)?.unit ??
      HarvestUnit.kg;
  int? days;
  bool initialized = false, busy = false;
  String? error;
  String get id => widget.plan?.id ?? widget.task!.id;
  bool get recurring =>
      widget.plan != null && widget.plan!.repeat != RepeatSchedule.none;
  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ref.watch(recordsProvider(RecordKind.reminder));
    if (!initialized && reminders.hasValue) {
      days =
          reminders.value!.where((r) => r['id'] == id).firstOrNull?['days']
              as int?;
      initialized = true;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit task & reminders')),
      body: OrchardForm(
        title: 'Task & reminders',
        subtitle: 'Update open work and choose when you would like a reminder.',
        icon: Icons.checklist,
        children: [
          const Text(
            'Edits apply to open work and future occurrences. Completed, skipped and cancelled work, target membership, recurrence anchors and linked activities are retained. Create a new task to change targets or recurrence.',
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
          ListTile(
            title: const Text('Due date'),
            subtitle: Text(
              '${due ?? 'Not set'}${recurring ? ' · recurrence anchor retained' : ''}',
            ),
            onTap: recurring
                ? null
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: due == null
                          ? DateTime.now()
                          : parseCalendarDate(due!),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) {
                      setState(() => due = calendarDate(d));
                    }
                  },
            trailing: recurring
                ? null
                : IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() => due = null),
                    icon: const Icon(Icons.clear),
                  ),
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
              decoration: const InputDecoration(labelText: 'Harvest quantity'),
              keyboardType: TextInputType.number,
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
          DropdownButtonFormField<int>(
            key: ValueKey('reminder-$initialized'),
            initialValue: days ?? -1,
            decoration: const InputDecoration(
              labelText: 'Reminder at 9 AM local time',
            ),
            items: [
              const DropdownMenuItem(value: -1, child: Text('Off')),
              for (final d in [0, 1, 3, 7])
                DropdownMenuItem(
                  value: d,
                  child: Text(d == 0 ? 'On due date' : '$d days before'),
                ),
            ],
            onChanged: (v) => setState(() => days = v == -1 ? null : v),
          ),
          const Text(
            'Reminders require notification permission. Dates without due dates do not notify. Android may delay delivery to save battery. Reopen the app after changing timezone. Each group receives one reminder per occurrence.',
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy || !initialized
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      if (days != null &&
                          !await ref
                              .read(reminderSchedulerProvider)
                              .requestPermission()) {
                        throw StateError(
                          'Notifications blocked. Enable OrchardAtlas notifications in device settings.',
                        );
                      }
                      final orchard = await ref.read(placeProvider.future),
                          repo = ref.read(orchardRepositoryProvider);
                      final harvest = eventType == ActivityType.harvest
                          ? Harvest(double.parse(quantity.text), unit)
                          : null;
                      requiredText(title.text, 'Task title');
                      final tasks = (await ref.read(tasksProvider.future))
                          .value;
                      if (widget.plan != null) {
                        final latest = (await ref.read(
                          taskPlansProvider.future,
                        )).firstWhere((p) => p.id == id);
                        final edited = editPlan(
                          latest,
                          title: title.text,
                          notes: notes.text,
                          dueDate: due,
                          eventType: eventType,
                          eventHarvest: harvest,
                        );
                        repo.saveTaskPlan(edited);
                        final current = occurrenceDates(
                          latest,
                          DateTime.now(),
                        ).last;
                        for (final t in tasks.where(
                          (t) =>
                              t.planId == id &&
                              t.status == TaskStatus.open &&
                              t.occurrenceOn == current,
                        )) {
                          repo.saveTask(
                            editOpenTask(
                              t,
                              title: title.text,
                              notes: notes.text,
                              dueDate: recurring ? t.dueDate : due,
                              eventType: t.itemId == null ? null : eventType,
                              eventHarvest: harvest,
                            ),
                          );
                        }
                      } else {
                        final latest = tasks.firstWhere((t) => t.id == id);
                        if (latest.status != TaskStatus.open) {
                          throw StateError(
                            'Only open tasks may be edited. Completion history is retained.',
                          );
                        }
                        repo.saveTask(
                          editOpenTask(
                            latest,
                            title: title.text,
                            notes: notes.text,
                            dueDate: due,
                            eventType: eventType,
                            eventHarvest: harvest,
                          ),
                        );
                      }
                      final records = ref.read(orchardRecordsProvider);
                      if (days == null) {
                        await records.removeRecord(
                          orchard.id,
                          RecordKind.reminder,
                          id,
                        );
                      } else {
                        await records.putRecord(
                          orchard.id,
                          RecordKind.reminder,
                          id,
                          {'days': days},
                        );
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = '$e');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Save task changes'),
          ),
        ],
      ),
    );
  }
}
