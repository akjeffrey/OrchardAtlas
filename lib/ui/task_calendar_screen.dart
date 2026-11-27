import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/task_calendar.dart';
import 'orchard_theme.dart';

class TaskCalendarScreen extends ConsumerStatefulWidget {
  const TaskCalendarScreen({super.key});
  @override
  ConsumerState<TaskCalendarScreen> createState() => _TaskCalendarScreenState();
}

class _TaskCalendarScreenState extends ConsumerState<TaskCalendarScreen> {
  List<Map<String, dynamic>> calendars = [];
  String? selected, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final key = await scope();
        final current = await ref.read(taskCalendarProvider).selected(key);
        if (mounted) setState(() => selected = current);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    });
  }

  Future<String> scope() async {
    final orchard = await ref.read(placeProvider.future);
    final user = ref.read(userProvider).valueOrNull;
    if (user == null) throw StateError('Sign in first');
    return '${user.id}/${orchard.id}';
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final key = await scope();
      final repo = ref.read(taskCalendarProvider);
      final rows = await repo.calendars();
      final current = await repo.selected(key);
      if (mounted) {
        setState(() {
          calendars = rows;
          selected = current;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose(String? id) async {
    setState(() => busy = true);
    try {
      await ref.read(taskCalendarProvider).select(await scope(), id);
      ref.read(calendarRefreshProvider.notifier).state++;
      if (mounted) {
        setState(() {
          selected = id;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Task calendar sync')),
    body: OrchardForm(
      title: 'Google Calendar',
      subtitle: 'Sync this orchard to a calendar on this phone.',
      icon: Icons.event,
      children: [
        const Text(
          'Add your Google account in the phone’s Calendar settings and enable calendar sync. Then choose its calendar below. Calendar access is requested only when you connect.',
        ),
        const Text(
          'OrchardAtlas sends dated tasks, date ranges and completion counts to your selected calendar. Repeating tasks are published 90 days ahead. Edit tasks in OrchardAtlas; calendar edits are not imported. Task names and notes will be visible to people who can read that calendar.',
        ),
        FilledButton.icon(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.calendar_month),
          label: const Text('Choose calendar / refresh access'),
        ),
        if (!busy && calendars.isEmpty)
          const Text(
            'No calendars loaded. Connect above. If none are available, add your Google account to the phone and enable its calendar.',
          ),
        for (final c in calendars)
          ListTile(
            leading: Icon(
              selected == c['id']
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(c['name'] as String),
            subtitle: Text(c['account'] as String? ?? ''),
            onTap: busy ? null : () => choose(c['id'] as String),
          ),
        if (selected != null) ...[
          const Text(
            'Connected. Changes sync while the app is open and on next launch. The phone uploads to Google when connected. Device calendar settings control upload timing.',
          ),
          OutlinedButton(
            onPressed: busy ? null : () => choose(null),
            child: const Text('Disconnect and remove exported tasks'),
          ),
        ],
        if (error != null) Text(error!),
        if (ref.watch(calendarErrorProvider) != null)
          Text(ref.watch(calendarErrorProvider)!),
        const Text(
          'Disconnecting or choosing another calendar removes only events created by this app for this orchard. Your other calendar events are kept. Local task data remains available offline.',
        ),
      ],
    ),
  );
}
