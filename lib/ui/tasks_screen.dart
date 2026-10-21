import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import '../domain/landscape.dart';
import '../domain/filters.dart';
import '../domain/work.dart';
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
                .read(commandsProvider)
                .changeTaskStatus(
                  task,
                  status,
                  ref.read(userProvider).valueOrNull?.id ??
                      ref.read(placeProvider).value!.ownerId,
                );
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

class TaskGroupScreen extends ConsumerStatefulWidget {
  const TaskGroupScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<TaskGroupScreen> createState() => _TaskGroupState();
}

class _TaskGroupState extends ConsumerState<TaskGroupScreen> {
  String? selected;
  String query = '';
  TaskStatus? status;
  @override
  Widget build(BuildContext context) {
    final plan = ref
        .watch(taskPlansProvider)
        .valueOrNull
        ?.where((p) => p.id == widget.id)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Group task checklist')),
      body: ref
          .watch(tasksProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorPanel(e),
            data: (snapshot) {
              final all = snapshot.value
                  .where((t) => t.groupId == widget.id || t.planId == widget.id)
                  .toList();
              if (all.isEmpty && plan == null) {
                return const ErrorPanel('Task group unavailable');
              }
              final dates =
                  all
                      .map((t) => t.occurrenceOn)
                      .whereType<String>()
                      .toSet()
                      .toList()
                    ..sort((a, b) => b.compareTo(a));
              final current = plan == null
                  ? dates.firstOrNull
                  : occurrenceDates(plan, DateTime.now()).last;
              if (current != null && !dates.contains(current)) {
                dates.insert(0, current);
              }
              final date = selected != null && dates.contains(selected)
                  ? selected
                  : current;
              final members = all
                  .where((t) => date == null || t.occurrenceOn == date)
                  .toList();
              final plants =
                  ref.watch(plantsProvider).valueOrNull?.value ??
                  <ManagedPlant>[];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    plan?.title ?? all.first.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(groupProgress(members)),
                  Text(
                    plan == null
                        ? 'Legacy checklist: existing membership retained.'
                        : 'New matching plants join automatically. Each occurrence retains its own completion history.',
                  ),
                  if (dates.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey('occurrence-$date'),
                      initialValue: date,
                      decoration: const InputDecoration(
                        labelText: 'Occurrence / history',
                      ),
                      items: [
                        for (final d in dates)
                          DropdownMenuItem(value: d, child: Text(d)),
                      ],
                      onChanged: (v) => setState(() => selected = v),
                    ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Filter checklist',
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: '',
                    decoration: const InputDecoration(
                      labelText: 'Completion filter',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All statuses'),
                      ),
                      for (final s in TaskStatus.values)
                        DropdownMenuItem(value: s.name, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(
                      () => status = v == ''
                          ? null
                          : TaskStatus.values.byName(v!),
                    ),
                  ),
                  if (members.isEmpty)
                    const Text(
                      'No matching targets yet. This task remains valid.',
                    ),
                  for (final t in members.where(
                    (t) =>
                        (status == null || t.status == status) &&
                        '${plants.where((p) => p.id == t.itemId).firstOrNull?.name ?? ''} ${t.title}'
                            .toLowerCase()
                            .contains(query.toLowerCase()),
                  ))
                    TaskMemberTile(t, showTitle: false),
                ],
              );
            },
          ),
    );
  }
}

class TasksPane extends ConsumerStatefulWidget {
  const TasksPane({super.key, this.itemId, this.taxonId});
  final String? taxonId;
  final String? itemId;
  @override
  ConsumerState<TasksPane> createState() => _TasksState();
}

class _TasksState extends ConsumerState<TasksPane> {
  TaskWindow window = TaskWindow.all;
  TaskSort sort = TaskSort.dueDate;
  String query = '', classification = '';
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final place = await ref.read(placeProvider.future);
        final saved = await ref
            .read(mapViewRepositoryProvider)
            .loadTaskSort(place.ownerId);
        if (mounted) {
          setState(() => sort = TaskSort.values.byName(saved ?? 'dueDate'));
        }
      } catch (_) {}
    });
  }

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
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Filter tasks'),
              onChanged: (q) => setState(() => query = q),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TaskSort>(
                    key: ValueKey(sort),
                    initialValue: sort,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sort tasks'),
                    items: [
                      for (final s in TaskSort.values)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            s == TaskSort.dueDate
                                ? 'Undated, next due, overdue'
                                : s.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) async {
                      setState(() => sort = v!);
                      try {
                        final place = await ref.read(placeProvider.future);
                        await ref
                            .read(mapViewRepositoryProvider)
                            .saveTaskSort(place.ownerId, v!.name);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Classification',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All types'),
                      ),
                      for (final t in ref.watch(taxonomyProvider).taxa)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => classification = v!),
                  ),
                ),
              ],
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
        'Due dates are recorded; background reminders are not available yet.',
      ),
      Expanded(
        child: ref
            .watch(tasksProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  ErrorPanel(e, retry: () => ref.invalidate(tasksProvider)),
              data: (snapshot) {
                final plans =
                    ref.watch(taskPlansProvider).valueOrNull ?? <TaskPlan>[];
                final taxonomy = ref.watch(taxonomyProvider);
                final selectedTaxon =
                    widget.taxonId ??
                    (classification.isEmpty ? null : classification);
                final taxa = selectedTaxon == null
                    ? null
                    : taxonomy.descendants(selectedTaxon);
                final plants =
                    ref.watch(plantsProvider).valueOrNull?.value ??
                    <ManagedPlant>[];
                final crops =
                    ref.watch(cropsProvider).valueOrNull?.value ??
                    <CropPlanting>[];
                final filtered =
                    snapshot.value
                        .where(
                          (t) =>
                              (widget.itemId == null ||
                                  t.itemId == widget.itemId) &&
                              (status == null || t.status == status) &&
                              taskInWindow(t, window, DateTime.now()) &&
                              '${t.title} ${t.notes} ${plants.where((p) => p.id == t.itemId).firstOrNull?.name ?? ''}'
                                  .toLowerCase()
                                  .contains(query.toLowerCase()) &&
                              (taxa == null ||
                                  plants.any(
                                    (p) =>
                                        p.id == t.itemId &&
                                        taxa.contains(p.taxonId),
                                  ) ||
                                  crops.any(
                                    (c) =>
                                        c.id == t.cropId &&
                                        taxa.contains(c.taxonId),
                                  )) &&
                              (t.planId == null ||
                                  plans
                                          .where((p) => p.id == t.planId)
                                          .firstOrNull ==
                                      null ||
                                  t.occurrenceOn ==
                                      occurrenceDates(
                                        plans.firstWhere(
                                          (p) => p.id == t.planId,
                                        ),
                                        DateTime.now(),
                                      ).last),
                        )
                        .toList()
                      ..sort(
                        (a, b) => compareTasks(a, b, sort, DateTime.now()),
                      );
                final emptyPlans = plans
                    .where(
                      (p) =>
                          !snapshot.value.any((t) => t.planId == p.id) &&
                          widget.itemId == null &&
                          (taxa == null ||
                              p.taxonId == null ||
                              taxonomy
                                  .descendants(p.taxonId!)
                                  .contains(selectedTaxon) ||
                              taxa.contains(p.taxonId)) &&
                          p.title.toLowerCase().contains(query.toLowerCase()),
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
                      child: entries.isEmpty && emptyPlans.isEmpty
                          ? const Center(
                              child: Text('No tasks match these filters.'),
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 96),
                              children: [
                                for (final plan in emptyPlans)
                                  ListTile(
                                    title: Text(plan.title),
                                    subtitle: const Text(
                                      'No matching targets yet · task saved',
                                    ),
                                    onTap: () =>
                                        context.push('/task-groups/${plan.id}'),
                                  ),
                                for (final task in entries)
                                  if (task.groupId != null &&
                                      widget.itemId == null)
                                    ListTile(
                                      leading: const Icon(Icons.checklist),
                                      title: Text(task.title),
                                      subtitle: Text(
                                        '${task.groupScope}\n${groupProgress(snapshot.value.where((t) => t.groupId == task.groupId && t.occurrenceOn == task.occurrenceOn).toList())}',
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
  SectionKind scopeKind = SectionKind.row;
  DateTime? dueDate;
  String? error;
  bool busy = false;
  RepeatSchedule repeat = RepeatSchedule.none;
  ActivityType? eventType;
  HarvestUnit eventUnit = HarvestUnit.kg;
  final eventQuantity = TextEditingController();
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
    eventQuantity.dispose();
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
      if (target.startsWith('__') ||
          repeat != RepeatSchedule.none ||
          eventType != null) {
        final crops = await ref.read(cropsProvider.future);
        final plan = TaskPlan(
          id: const Uuid().v4(),
          propertyId: place.id,
          title: title.text,
          createdAt: DateTime.now().toUtc(),
          target: target == '__group__'
              ? 'plants'
              : target == '__sections__'
              ? 'sections'
              : target == '__crops__'
              ? 'crops'
              : target.startsWith('section:')
              ? 'section'
              : target.startsWith('crop:')
              ? 'crop'
              : target.isEmpty
              ? 'property'
              : 'plant',
          itemId:
              target.isEmpty || target.startsWith('__') || target.contains(':')
              ? null
              : target,
          sectionId: target.startsWith('section:')
              ? target.substring(8)
              : scopeSection.isEmpty
              ? null
              : scopeSection,
          cropId: target.startsWith('crop:') ? target.substring(5) : null,
          taxonId: scopeTaxon.isEmpty ? null : scopeTaxon,
          sectionKind: scopeKind,
          dueDate: dueDate == null ? null : calendarDate(dueDate!),
          repeat: repeat,
          eventType: eventType,
          eventHarvest: eventType == ActivityType.harvest
              ? Harvest(double.parse(eventQuantity.text), eventUnit)
              : null,
          notes: notes.text,
        );
        repo.saveTaskPlan(plan);
        final existing = await ref.read(tasksProvider.future);
        for (final task in expandPlans(
          plans: [plan],
          existing: existing.value,
          plants: plants.value,
          sections: sections.value,
          crops: crops.value,
          taxonomy: ref.read(taxonomyProvider),
          now: DateTime.now(),
        )) {
          repo.saveTask(task);
        }
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
      if (!mounted) return;
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
            '__sections__': 'Group: areas / rows',
            '__crops__': 'Group: seasonal crops',
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
              if (target.startsWith('__')) ...[
                if (target == '__sections__')
                  DropdownButtonFormField<SectionKind>(
                    initialValue: scopeKind,
                    decoration: const InputDecoration(
                      labelText: 'Each target is a',
                    ),
                    items: [
                      for (final k in SectionKind.values)
                        DropdownMenuItem(value: k, child: Text(k.name)),
                    ],
                    onChanged: (k) => setState(() => scopeKind = k!),
                  ),
                if (target != '__sections__')
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
                  target == '__group__'
                      ? '$count active plants will be included. New matching plants will be included automatically. Zero matches is valid.'
                      : '${target == '__sections__' ? sections.where((s) => s.kind == scopeKind && (sectionIds == null || sectionIds.contains(s.id))).length : crops.where((c) => c.status == CropStatus.growing && (taxonIds == null || taxonIds.contains(c.taxonId)) && (sectionIds == null || sectionIds.contains(c.sectionId))).length} targets will be included. New matching targets will be included automatically. Zero matches is valid.',
                ),
              ],
              DropdownButtonFormField<RepeatSchedule>(
                initialValue: repeat,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: [
                  for (final r in RepeatSchedule.values)
                    DropdownMenuItem(value: r, child: Text(r.name)),
                ],
                onChanged: (r) => setState(() => repeat = r!),
              ),
              DropdownButtonFormField<String>(
                initialValue: eventType?.name ?? '',
                decoration: const InputDecoration(
                  labelText: 'Create plant activity on completion (optional)',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('No activity')),
                  for (final t in ActivityType.values.where(
                    (t) => t != ActivityType.photo,
                  ))
                    DropdownMenuItem(
                      value: t.name,
                      child: Text(activityLabel(t.name)),
                    ),
                ],
                onChanged: (t) => setState(
                  () => eventType = t == ''
                      ? null
                      : ActivityType.values.byName(t!),
                ),
              ),
              if (eventType == ActivityType.harvest) ...[
                TextField(
                  controller: eventQuantity,
                  decoration: const InputDecoration(
                    labelText: 'Harvest quantity per completed plant',
                  ),
                ),
                DropdownButtonFormField<HarvestUnit>(
                  initialValue: eventUnit,
                  items: [
                    for (final u in HarvestUnit.values)
                      DropdownMenuItem(value: u, child: Text(u.name)),
                  ],
                  onChanged: (u) => eventUnit = u!,
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
                      : target.startsWith('__')
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
