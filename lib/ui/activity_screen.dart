import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen(this.itemId, {super.key});
  final String itemId;
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<ActivityScreen> {
  ActivityType type = ActivityType.note;
  HarvestUnit unit = HarvestUnit.kg;
  DateTime date = DateTime.now();
  final notes = TextEditingController();
  final quantity = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    notes.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final place = await ref.read(placeProvider.future);
      final user = ref.read(userProvider).valueOrNull;
      if (user == null) throw StateError('Please sign in again');
      final plants = await ref.read(plantsProvider.future);
      if (!plants.value.any((p) => p.id == widget.itemId)) {
        throw StateError('Plant unavailable');
      }
      if (!mounted) return;
      ref
          .read(commandsProvider)
          .record(
            place: place,
            itemId: widget.itemId,
            authorId: user.id,
            type: type,
            date: date,
            notes: notes.text,
            harvest: type == ActivityType.harvest
                ? Harvest(double.parse(quantity.text), unit)
                : null,
          );
      context.go('/plants/${widget.itemId}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record Activity / Harvest')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<ActivityType>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Activity'),
          items: [
            for (final t in ActivityType.values.where(
              (t) => t != ActivityType.photo,
            ))
              DropdownMenuItem(value: t, child: Text(activityLabel(t.name))),
          ],
          onChanged: busy ? null : (value) => setState(() => type = value!),
        ),
        ListTile(
          title: Text('Activity date: ${calendarDate(date)}'),
          trailing: const Icon(Icons.calendar_today),
          onTap: busy
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100, 12, 31),
                  );
                  if (picked != null && mounted) setState(() => date = picked);
                },
        ),
        if (type == ActivityType.harvest) ...[
          TextField(
            controller: quantity,
            decoration: const InputDecoration(labelText: 'Harvest quantity'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          DropdownButtonFormField<HarvestUnit>(
            initialValue: unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: [
              for (final u in HarvestUnit.values)
                DropdownMenuItem(value: u, child: Text(u.name)),
            ],
            onChanged: busy ? null : (value) => setState(() => unit = value!),
          ),
        ],
        TextField(
          controller: notes,
          maxLines: 5,
          maxLength: 10000,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save activity locally'),
        ),
      ],
    ),
  );
}
