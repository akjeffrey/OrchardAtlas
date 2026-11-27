import 'package:flutter/material.dart';
import '../domain/models.dart';

class TaskScheduleFields extends StatelessWidget {
  const TaskScheduleFields({super.key, required this.start, required this.end,
    required this.offsets, required this.onDates, required this.onReminders,
    this.fixedStart = false});
  final String? start, end;
  final List<int> offsets;
  final bool fixedStart;
  final void Function(String?, String?) onDates;
  final ValueChanged<List<int>> onReminders;
  @override
  Widget build(BuildContext context) => Column(children: [
    ListTile(title: const Text('Start date'), subtitle: Text(start ?? 'Not set'),
      trailing: fixedStart ? const Icon(Icons.repeat) : const Icon(Icons.calendar_month),
      onTap: fixedStart ? null : () async {
        final d = await showDatePicker(context: context,
          initialDate: start == null ? DateTime.now() : parseCalendarDate(start!),
          firstDate: DateTime(1900), lastDate: DateTime(2100,12,31));
        if (d != null) {
          final next = calendarDate(d);
          onDates(next, end != null && end!.compareTo(next) < 0 ? null : end);
        }
      }),
    if (fixedStart) const Text('The start date anchors this repeating task. Its date range repeats with each occurrence.'),
    ListTile(title: const Text('End date (optional)'), subtitle: Text(end ?? 'Single day'),
      trailing: end == null ? null : IconButton(tooltip: 'Clear end date',
        icon: const Icon(Icons.clear), onPressed: () => onDates(start,null)),
      onTap: start == null ? null : () async {
        final first = parseCalendarDate(start!);
        final d = await showDatePicker(context: context,
          initialDate: end == null ? first : parseCalendarDate(end!),
          firstDate: first, lastDate: DateTime(2100,12,31));
        if (d != null) onDates(start,calendarDate(d));
      }),
    const Align(alignment: Alignment.centerLeft, child: Text('Reminders · 9 AM local time')),
    for (final days in offsets) ListTile(
      title: Text(days == 0 ? 'On start date' : days % 7 == 0 ? '${days ~/ 7} week(s) before start' : '$days day(s) before start'),
      trailing: IconButton(tooltip: 'Remove reminder', icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => onReminders(offsets.where((d) => d != days).toList()))),
    OutlinedButton.icon(icon: const Icon(Icons.add_alert_outlined), label: const Text('Add reminder'),
      onPressed: offsets.length >= 10 ? null : () async {
        final days = await showDialog<int>(context: context, builder: (_) => const _ReminderDialog());
        if (days != null) onReminders({...offsets,days}.toList()..sort());
      }),
    const Text('Up to 10 reminders before the start. Permission is requested on save. Past reminders are skipped. Battery settings may delay delivery.'),
  ]);
}
class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog();
  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}
class _ReminderDialogState extends State<_ReminderDialog> {
  final count = TextEditingController(text: '1');
  int unit = 1;
  String? error;
  @override
  void dispose() { count.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Reminder before start'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: count, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'How many?',errorText:error)),
      DropdownButtonFormField<int>(initialValue:unit,items:const [
        DropdownMenuItem(value:1,child:Text('Days')),
        DropdownMenuItem(value:7,child:Text('Weeks'))],onChanged:(v)=>setState(()=>unit=v!)),
      const Text('Use 0 for the start date. Maximum 365 days before start.'),
    ]), actions: [TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){
        final n=int.tryParse(count.text);
        if(n==null||n<0||n*unit>365){setState(()=>error='Enter 0–${365 ~/ unit}');return;}
        Navigator.pop(context,n*unit);
      },child:const Text('Add reminder'))]);
}
