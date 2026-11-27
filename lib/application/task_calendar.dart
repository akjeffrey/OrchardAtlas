import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task_calendar.dart';
import '../domain/work.dart';
import '../data/task_calendar_device.dart';
import 'providers.dart';

final taskCalendarProvider = Provider<TaskCalendarRepository>(
  (ref) => DeviceTaskCalendar(),
);
final calendarRefreshProvider = StateProvider<int>((ref) => 0);
final calendarErrorProvider = StateProvider<String?>((ref) => null);
final calendarWorkerProvider = Provider<void>((ref) {
  ref.watch(calendarRefreshProvider);
  final orchard = ref.watch(placeProvider).asData?.value;
  final user = ref.watch(userProvider).asData?.value;
  final tasks = ref.watch(tasksProvider).asData?.value.value;
  final plans = ref.watch(taskPlansProvider).asData?.value;
  final plants = ref.watch(plantsProvider).asData?.value.value;
  final crops = ref.watch(cropsProvider).asData?.value.value;
  final sections = ref.watch(sectionsProvider).asData?.value.value;
  final now = ref.watch(minuteClockProvider);
  final taxonomy = ref.watch(taxonomyProvider);
  final device = ref.watch(taskCalendarProvider);
  if (orchard == null ||
      user == null ||
      tasks == null ||
      plans == null ||
      plants == null ||
      crops == null ||
      sections == null) {
    return;
  }
  var active = true;
  final timer = Timer(const Duration(seconds: 2), () async {
    try {
      final scope = '${user.id}/${orchard.id}';
      if (await device.selected(scope) == null) return;
      final all = projectedTaskEntries(
        plans: plans,
        tasks: tasks,
        plants: plants,
        sections: sections,
        crops: crops,
        taxonomy: taxonomy,
        through: now.add(const Duration(days: 90)),
      );
      await device.replace(scope, taskCalendarEvents(all));
      if (active) ref.read(calendarErrorProvider.notifier).state = null;
    } catch (e) {
      if (!active) return;
      ref.read(calendarErrorProvider.notifier).state =
          'Calendar sync pending. Check calendar access in Settings. $e';
    }
  });
  ref.onDispose(() {
    active = false;
    timer.cancel();
  });
});
