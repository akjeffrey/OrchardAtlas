import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/filters.dart';
import 'common.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key, this.itemId});
  final String? itemId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plant tasks')),
    body: TasksPane(itemId: itemId),
  );
}

class TasksPane extends ConsumerStatefulWidget {
  const TasksPane({super.key, this.itemId});
  final String? itemId;
  @override
  ConsumerState<TasksPane> createState() => _TasksState();
}

class _TasksState extends ConsumerState<TasksPane> {
  TaskWindow window = TaskWindow.all;
  TaskStatus? status = TaskStatus.open;
  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider).valueOrNull?.value ?? [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TaskWindow>(
                  initialValue: window,
                  decoration: const InputDecoration(labelText: 'Due window'),
                  items: [
                    for (final w in TaskWindow.values)
                      DropdownMenuItem(
                        value: w,
                        child: Text(switch (w) {
                          TaskWindow.all => 'All dates',
                          TaskWindow.today => 'Today / overdue',
                          TaskWindow.thisWeek => 'This week',
                          TaskWindow.upcoming => 'Upcoming / undated',
                        }),
                      ),
                  ],
                  onChanged: (value) => setState(() => window = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: status?.name ?? 'all',
                  decoration: const InputDecoration(labelText: 'Task status'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All statuses'),
                    ),
                    for (final s in TaskStatus.values)
                      DropdownMenuItem(value: s.name, child: Text(s.name)),
                  ],
                  onChanged: (value) => setState(
                    () => status = value == 'all'
                        ? null
                        : TaskStatus.values.byName(value!),
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => context.push('/tasks/new', extra: widget.itemId),
          icon: const Icon(Icons.add_task),
          label: const Text('Add task'),
        ),
        const Text(
          'Due dates are recorded; no background reminders in this trial.',
        ),
        Expanded(
          child: ref
              .watch(tasksProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    ErrorPanel(e, retry: () => ref.invalidate(tasksProvider)),
                data: (snapshot) {
                  final tasks = snapshot.value
                      .where(
                        (t) =>
                            (widget.itemId == null ||
                                t.itemId == widget.itemId) &&
                            (status == null || t.status == status) &&
                            taskInWindow(t, window, DateTime.now()),
                      )
                      .toList();
                  return Column(
                    children: [
                      SyncStatus(snapshot),
                      Expanded(
                        child: tasks.isEmpty
                            ? const Center(
                                child: Text('No tasks match these filters.'),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 96),
                                itemCount: tasks.length,
                                itemBuilder: (context, i) {
                                  final task = tasks[i];
                                  final target = plants
                                      .where((p) => p.id == task.itemId)
                                      .firstOrNull;
                                  return ListTile(
                                    title: Text(task.title),
                                    subtitle: Text(
                                      '${target?.name ?? (task.itemId == null ? 'Whole property' : 'Unavailable plant')} · ${task.dueDate ?? 'No due date'} · ${task.status.name}${task.notes.isEmpty ? '' : '\n${task.notes}'}',
                                    ),
                                    trailing: PopupMenuButton<TaskStatus>(
                                      tooltip: 'Change task status',
                                      onSelected: (value) {
                                        try {
                                          ref
                                              .read(orchardRepositoryProvider)
                                              .saveTask(task.withStatus(value));
                                        } catch (e) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                SnackBar(content: Text('$e')),
                                              );
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        for (final s in TaskStatus.values)
                                          PopupMenuItem(
                                            value: s,
                                            child: Text(switch (s) {
                                              TaskStatus.open => 'Reopen',
                                              TaskStatus.completed =>
                                                'Complete',
                                              TaskStatus.cancelled =>
                                                'Cancel task',
                                            }),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.itemId});
  final String? itemId;
  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<TaskFormScreen> {
  final title = TextEditingController(), notes = TextEditingController();
  String? itemId;
  DateTime? dueDate;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    itemId = widget.itemId;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final place = await ref.read(placeProvider.future);
      if (!mounted) return;
      ref
          .read(orchardRepositoryProvider)
          .saveTask(
            OrchardTask(
              id: const Uuid().v4(),
              propertyId: place.id,
              title: title.text,
              notes: notes.text,
              itemId: itemId,
              dueDate: dueDate == null ? null : calendarDate(dueDate!),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plants = ref.watch(plantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add task')),
      body: plants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorPanel(e),
        data: (snapshot) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: title,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Task title'),
            ),
            DropdownButtonFormField<String>(
              initialValue: itemId ?? '',
              decoration: const InputDecoration(labelText: 'Target'),
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Whole property'),
                ),
                for (final p in snapshot.value)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.name}${p.status == ItemStatus.archived ? ' (archived)' : ''}',
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) =>
                        setState(() => itemId = value == '' ? null : value),
            ),
            ListTile(
              title: const Text('Due date (optional)'),
              subtitle: Text(
                dueDate == null ? 'Not set' : calendarDate(dueDate!),
              ),
              onTap: busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dueDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (date != null && mounted) {
                        setState(() => dueDate = date);
                      }
                    },
              trailing: dueDate == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear due date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => dueDate = null),
                    ),
            ),
            TextField(
              controller: notes,
              maxLines: 4,
              maxLength: 10000,
              decoration: const InputDecoration(labelText: 'Task notes'),
            ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save task'),
            ),
          ],
        ),
      ),
    );
  }
}
