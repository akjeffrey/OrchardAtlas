import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import 'common.dart';

class EventsTable extends StatefulWidget {
  const EventsTable({super.key, required this.events, this.names = const {}});
  final List<PlantEvent> events;
  final Map<String, String> names;
  @override
  State<EventsTable> createState() => _EventsState();
}

class _EventsState extends State<EventsTable> {
  String query = '';
  ActivityType? type;
  DateTimeRange? dates;
  @override
  Widget build(BuildContext context) {
    final events = widget.events
        .where(
          (e) =>
              (type == null || e.type == type) &&
              (dates == null ||
                  e.activityDate.compareTo(calendarDate(dates!.start)) >= 0 &&
                      e.activityDate.compareTo(calendarDate(dates!.end)) <=
                          0) &&
              '${widget.names[e.itemId] ?? ''} ${activityLabel(e.type.name)} ${e.notes}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Filter activities'),
          onChanged: (q) => setState(() => query = q),
        ),
        DropdownButtonFormField<String>(
          initialValue: '',
          decoration: const InputDecoration(labelText: 'Activity type'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All activities')),
            for (final t in ActivityType.values)
              DropdownMenuItem(
                value: t.name,
                child: Text(activityLabel(t.name)),
              ),
          ],
          onChanged: (t) => setState(
            () => type = t == '' ? null : ActivityType.values.byName(t!),
          ),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(1800),
                  lastDate: DateTime(2100),
                  initialDateRange: dates,
                );
                if (range != null && mounted) setState(() => dates = range);
              },
              child: Text(
                dates == null
                    ? 'Filter dates'
                    : '${calendarDate(dates!.start)} – ${calendarDate(dates!.end)}',
              ),
            ),
            if (dates != null)
              TextButton(
                onPressed: () => setState(() => dates = null),
                child: const Text('Clear dates'),
              ),
          ],
        ),
        if (events.isEmpty) const Text('No activities match.'),
        for (final e in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${activityLabel(e.type.name)} · ${e.activityDate}'),
            subtitle: Text(
              [
                if (widget.names[e.itemId] != null) widget.names[e.itemId]!,
                if (e.harvest != null)
                  '${e.harvest!.quantity} ${e.harvest!.unit.name}',
                if (e.notes.isNotEmpty) e.notes,
              ].join('\n'),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => context.push('/plants/${e.itemId}/activity', extra: e),
          ),
      ],
    );
  }
}
