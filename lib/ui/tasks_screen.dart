import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';
import '../domain/filters.dart';
import 'common.dart';
import 'sections_screen.dart';

class TaskTarget {
  const TaskTarget({this.sectionId, this.cropId});
  final String? sectionId, cropId;
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key, this.itemId});
  final String? itemId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plant tasks')),
    body: TasksPane(itemId: itemId),
  );
}

class TaskMemberTile extends ConsumerWidget {
  const TaskMemberTile(this.task, {super.key, this.showTitle = true});
  final OrchardTask task;
  final bool showTitle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plant = ref
        .watch(plantsProvider)
        .valueOrNull
        ?.value
        .where((p) => p.id == task.itemId)
        .firstOrNull;
    final section = ref
        .watch(sectionsProvider)
        .valueOrNull
        ?.value
        .where((s) => s.id == task.sectionId)
        .firstOrNull;
    final crop = ref
        .watch(cropsProvider)
        .valueOrNull
        ?.value
        .where((c) => c.id == task.cropId)
        .firstOrNull;
    final target =
        plant?.name ??
        section?.name ??
        crop?.label ??
        (task.itemId == null && task.sectionId == null && task.cropId == null
            ? 'Whole property'
            : 'Target unavailable');
    return ListTile(
      title: Text(showTitle ? task.title : target),
      subtitle: Text(
        '${showTitle ? '$target · ' : ''}${task.dueDate ?? 'No due date'} · ${task.status.name}${task.completedOn == null ? '' : ' · completed ${task.completedOn}'}${task.notes.isEmpty ? '' : '\n${task.notes}'}',
      ),
      onTap: plant != null
          ? () => context.push('/plants/${plant.id}')
          : section != null
          ? () => context.push('/sections/${section.id}')
          : crop != null
          ? () => context.push('/crops/${crop.id}')
          : null,
      trailing: PopupMenuButton<TaskStatus>(
        tooltip: 'Change task status',
        onSelected: (status) {
          try {
            ref
                .read(orchardRepositoryProvider)
                .saveTask(task.withStatus(status));
          } catch (e) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          }
        },
        itemBuilder: (_) => [
          for (final status in TaskStatus.values)
            PopupMenuItem(
              value: status,
              child: Text(switch (status) {
                TaskStatus.open => 'Reopen',
                TaskStatus.completed => 'Complete',
                TaskStatus.cancelled => 'Cancel task',
                TaskStatus.skipped => 'Skip',
              }),
            ),
        ],
      ),
    );
  }
}

String groupProgress(List<OrchardTask> members) {
  final done = members.where((t) => t.status == TaskStatus.completed).length,
      open = members.where((t) => t.status == TaskStatus.open).length;
  return '$done of ${members.length} completed · $open remaining · ${members.length - done - open} skipped/cancelled';
}

class TaskGroupScreen extends ConsumerWidget {
  const TaskGroupScreen(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Group task checklist')),
    body: ref
        .watch(tasksProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(e),
          data: (snapshot) {
            final members = snapshot.value
                .where((t) => t.groupId == id)
                .toList();
            if (members.isEmpty) {
              return const ErrorPanel('Task group unavailable');
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  members.first.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(members.first.groupScope),
                Text(groupProgress(members)),
                const Text(
                  'Membership was captured when this task was created. Complete each plant on the day you work on it. Tap a plant to record a separate activity.',
                ),
                SyncStatus(snapshot),
                for (final task in members)
                  TaskMemberTile(task, showTitle: false),
              ],
            );
          },
        ),
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
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<TaskWindow>(
                initialValue: window,
                isExpanded: true,
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
                      }, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (w) => setState(() => window = w!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: status?.name ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Task status'),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All statuses'),
                  ),
                  for (final s in TaskStatus.values)
                    DropdownMenuItem(value: s.name, child: Text(s.name)),
                ],
                onChanged: (s) => setState(
                  () =>
                      status = s == 'all' ? null : TaskStatus.values.byName(s!),
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
                final filtered = snapshot.value
                    .where(
                      (t) =>
                          (widget.itemId == null ||
                              t.itemId == widget.itemId) &&
                          (status == null || t.status == status) &&
                          taskInWindow(t, window, DateTime.now()),
                    )
                    .toList();
                final seen = <String>{};
                final entries = filtered
                    .where(
                      (t) =>
                          widget.itemId != null ||
                          t.groupId == null ||
                          seen.add(t.groupId!),
                    )
                    .toList();
                return Column(
                  children: [
                    SyncStatus(snapshot),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Text('No tasks match these filters.'),
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 96),
                              children: [
                                for (final task in entries)
                                  if (task.groupId != null &&
                                      widget.itemId == null)
                                    ListTile(
                                      leading: const Icon(Icons.checklist),
                                      title: Text(task.title),
                                      subtitle: Text(
                                        '${task.groupScope}\n${groupProgress(snapshot.value.where((t) => t.groupId == task.groupId).toList())}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => context.push(
                                        '/task-groups/${task.groupId}',
                                      ),
                                    )
                                  else
                                    TaskMemberTile(task),
                              ],
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

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.itemId, this.sectionId, this.cropId});
  final String? itemId, sectionId, cropId;
  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<TaskFormScreen> {
  final title = TextEditingController(), notes = TextEditingController();
  String target = '', scopeTaxon = '', scopeSection = '';
  DateTime? dueDate;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    target =
        widget.itemId ??
        (widget.sectionId != null
            ? 'section:${widget.sectionId}'
            : widget.cropId != null
            ? 'crop:${widget.cropId}'
            : '');
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final place = await ref.read(placeProvider.future);
      final plants = await ref.read(plantsProvider.future);
      final sections = await ref.read(sectionsProvider.future);
      if (!mounted) return;
      final repo = ref.read(orchardRepositoryProvider);
      if (target == '__group__') {
        repo.saveTaskGroup(
          groupPlantTasks(
            propertyId: place.id,
            title: title.text,
            plants: plants.value,
            taxonomy: ref.read(taxonomyProvider),
            sections: sections.value,
            newId: const Uuid().v4,
            taxonId: scopeTaxon.isEmpty ? null : scopeTaxon,
            sectionId: scopeSection.isEmpty ? null : scopeSection,
            dueDate: dueDate == null ? null : calendarDate(dueDate!),
            notes: notes.text,
          ),
        );
      } else {
        repo.saveTask(
          OrchardTask(
            id: const Uuid().v4(),
            propertyId: place.id,
            title: title.text,
            notes: notes.text,
            itemId: target.isEmpty || target.contains(':') ? null : target,
            sectionId: target.startsWith('section:')
                ? target.substring(8)
                : null,
            cropId: target.startsWith('crop:') ? target.substring(5) : null,
            dueDate: dueDate == null ? null : calendarDate(dueDate!),
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
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
    final sections =
        ref.watch(sectionsProvider).valueOrNull?.value ?? <OrchardSection>[];
    final crops =
        ref.watch(cropsProvider).valueOrNull?.value ?? <CropPlanting>[];
    final taxonomy = ref.watch(taxonomyProvider);
    final taxonIds = scopeTaxon.isEmpty
            ? null
            : taxonomy.descendants(scopeTaxon),
        sectionIds = scopeSection.isEmpty
            ? null
            : sectionDescendants(scopeSection, sections);
    return Scaffold(
      appBar: AppBar(title: const Text('Add task')),
      body: plants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorPanel(e),
        data: (snapshot) {
          final count = snapshot.value
              .where(
                (p) =>
                    p.status == ItemStatus.active &&
                    (taxonIds == null || taxonIds.contains(p.taxonId)) &&
                    (sectionIds == null || sectionIds.contains(p.sectionId)),
              )
              .length;
          final choices = <String, String>{
            '': 'Whole property',
            '__group__': 'Group: all matching plants',
            for (final p in snapshot.value)
              p.id:
                  '${p.name}${p.status == ItemStatus.archived ? ' (archived)' : ''}',
            for (final s in sections)
              'section:${s.id}': 'Area / row: ${sectionPath(s, sections)}',
            for (final c in crops)
              'crop:${c.id}': 'Crop: ${c.label} · ${c.season}',
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: title,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Task title'),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('task-target-$target-${choices.length}'),
                initialValue: choices.containsKey(target) ? target : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Target'),
                items: [
                  for (final e in choices.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => target = value!),
              ),
              if (target == '__group__') ...[
                DropdownButtonFormField<String>(
                  initialValue: scopeTaxon,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'All plants classified as',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All classifications'),
                    ),
                    for (final t in taxonomy.taxa)
                      DropdownMenuItem(
                        value: t.id,
                        child: Text(
                          taxonomy
                              .ancestry(t.id)
                              .map((a) => a.name)
                              .join(' › '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => scopeTaxon = id!),
                ),
                SectionPicker(
                  value: scopeSection.isEmpty ? null : scopeSection,
                  label: 'Within area / row (includes descendants)',
                  empty: 'Whole property',
                  onChanged: (id) => setState(() => scopeSection = id ?? ''),
                ),
                Text(
                  '$count active plants will be included. New plants added later are not included automatically.',
                ),
              ],
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
                child: Text(
                  busy
                      ? 'Saving…'
                      : target == '__group__'
                      ? 'Create group checklist'
                      : 'Save task',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
