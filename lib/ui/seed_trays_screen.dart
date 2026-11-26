import 'package:flutter/material.dart';
import '../domain/extensions.dart';
import 'seed_packet_photos.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../application/seed_trays.dart';
import '../domain/models.dart';
import '../domain/seed_trays.dart';
import 'classification_picker.dart';
import 'icon_picker.dart';
import 'orchard_theme.dart';
import 'common.dart';

Future<void> addSeedTray(BuildContext context) => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const SeedTrayForm()),
);

class SeedStarterPane extends ConsumerWidget {
  const SeedStarterPane({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(seedTraysProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorPanel(e, retry: () => ref.invalidate(seedTraysProvider)),
        data: (trays) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const FormIntro(
              title: 'Seed Starter',
              subtitle: 'Create a named tray, then select cells, rows or columns to record seeds and plants.',
              icon: Icons.grid_view,
            ),
            if (trays.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No seed trays yet. Tap Add tray to choose its rows and columns.',
                  ),
                ),
              ),
            for (final tray in trays)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.grid_on, color: OrchardBrand.leaf),
                  title: Text(tray.name),
                  subtitle: Text(
                    '${tray.rows} rows × ${tray.columns} columns · ${tray.capacity} cells',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SeedTrayDetail(tray.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class SeedTrayForm extends ConsumerStatefulWidget {
  const SeedTrayForm({super.key});
  @override
  ConsumerState<SeedTrayForm> createState() => _SeedTrayFormState();
}

class _SeedTrayFormState extends ConsumerState<SeedTrayForm> {
  final name = TextEditingController(),
      rows = TextEditingController(text: '6'),
      columns = TextEditingController(text: '12');
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    rows.dispose();
    columns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New seed tray')),
    body: OrchardForm(
      title: 'Create a tray',
      subtitle: 'Enter its name and cell layout. Rows and columns stay fixed after creation.',
      icon: Icons.grid_on,
      children: [
        TextField(
          controller: name,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Tray name'),
        ),
        TextField(
          controller: rows,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Rows',
            helperText: '1–24',
          ),
        ),
        TextField(
          controller: columns,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Columns',
            helperText: '1–24; up to 400 cells total',
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    final place = await ref.read(placeProvider.future);
                    final tray = SeedTray(
                      id: const Uuid().v4(),
                      propertyId: place.id,
                      name: name.text,
                      rows: int.parse(rows.text),
                      columns: int.parse(columns.text),
                      createdAt: DateTime.now().toUtc(),
                    );
                    await ref
                        .read(seedTrayRepositoryProvider)
                        .createSeedTray(tray);
                    if (context.mounted) {
                      Navigator.pushReplacement<void, void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SeedTrayDetail(tray.id),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Saving…' : 'Create tray'),
        ),
      ],
    ),
  );
}

class SeedTrayDetail extends ConsumerStatefulWidget {
  const SeedTrayDetail(this.id, {super.key});
  final String id;
  @override
  ConsumerState<SeedTrayDetail> createState() => _TrayDetailState();
}

class _TrayDetailState extends ConsumerState<SeedTrayDetail> {
  Set<TrayPosition> selected = {};
  bool busy = false;
  String? error;
  void toggle(Set<TrayPosition> group) =>
      setState(() => selected = toggleTraySelection(selected, group));
  Future<bool> confirm(String title, String message, {String actionLabel='Continue'}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> rename(SeedTray tray) async {
    var value = tray.name;
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename tray'),
        content: TextFormField(
          initialValue: tray.name,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Tray name'),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, value),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(seedTrayRepositoryProvider)
          .renameSeedTray(tray.propertyId, tray.id, result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> assign(
    SeedTray tray,
    Map<TrayPosition, TrayAssignment> cells,
  ) async {
    final positions = Set<TrayPosition>.of(selected);
    final result = await Navigator.push<_PlantingDraft>(
      context,
      MaterialPageRoute<_PlantingDraft>(
        builder: (_) => TrayAssignmentForm(
          count: positions.length,
          initial: positions.length == 1 ? cells[positions.single] : null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final latest = ref.read(trayCellsProvider(tray.id)).asData?.value ?? cells;
    final occupied = positions.where(latest.containsKey).length;
    if (occupied > 0 &&
        !await confirm(
          'Replace cell contents?',
          '$occupied selected cell(s) already contain seeds or plants. Their entries will be replaced.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(seedTrayRepositoryProvider)
          .assignTrayCells(tray, positions, result.assignment,packetPhotos:result.photos);
      if (mounted) setState(() => selected = {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transplant(SeedTray tray,Map<TrayPosition,TrayAssignment> cells,{bool undo=false}) async {
    final positions=selected.where(cells.containsKey).toSet();
    String? date;
    if(undo) {
      if(!await confirm('Undo transplant?','The selected cells will return to their growing appearance. Planting details and packet photos are retained.'))return;
    } else {
      final picked=await showDatePicker(context:context,initialDate:DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));
      if(picked==null)return;
      date=calendarDate(picked);
    }
    if(!mounted)return;
    setState(()=>busy=true);
    try{await ref.read(seedTrayRepositoryProvider).setTrayTransplantDate(tray,positions,date);if(mounted)setState(()=>selected={});}
    catch(e){if(mounted)setState(()=>error='$e');}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> deleteTray(SeedTray tray) async {
    if(!await confirm('Delete tray?','Delete ${tray.name}, all its cell entries and seed packet photos? This cannot be undone.',actionLabel:'Delete tray'))return;
    if(!mounted)return;
    setState(()=>busy=true);
    try {
      await ref.read(seedTrayRepositoryProvider).deleteSeedTray(tray.propertyId,tray.id);
      if(mounted)Navigator.maybePop(context);
    }catch(e){if(mounted)setState(()=>error='Could not finish deletion: $e. Reconnect and retry Delete tray.');}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override
  Widget build(BuildContext context) {
    final trays = ref.watch(seedTraysProvider);
    return trays.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: ErrorPanel(e)),
      data: (all) {
        final tray = all.where((t) => t.id == widget.id).firstOrNull;
        if (tray == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Seed tray')),
            body: const ErrorPanel('Tray unavailable in this orchard'),
          );
        }
        final canEdit = ref.watch(canEditOrchardProvider) && !tray.deleting;
        return Scaffold(
          appBar: AppBar(
            title: Text(tray.name),
            actions: [
              if(ref.watch(canEditOrchardProvider))IconButton(tooltip:'Delete tray',icon:const Icon(Icons.delete_outline),onPressed:busy?null:()=>deleteTray(tray)),
              if (canEdit)
                IconButton(
                  tooltip: 'Rename tray',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => rename(tray),
                ),
            ],
          ),
          body: ref
              .watch(trayCellsProvider(tray.id))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorPanel(e),
                data: (cells) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if(tray.deleting)const Text('Deletion started. Retry Delete tray to finish cleanup.'),
                          Text(
                            '${tray.rows} rows × ${tray.columns} columns · ${cells.length}/${tray.capacity} occupied',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap cells to select them. R selects a whole row; C selects a whole column. Scroll across or down for larger trays.',
                          ),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${selected.length} selected',
                                key: const ValueKey('tray-selection-count'),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => toggle(tray.positions),
                                child: const Text('Select all'),
                              ),
                              TextButton(
                                onPressed: busy || selected.isEmpty
                                    ? null
                                    : () => setState(() => selected = {}),
                                child: const Text('Clear selection'),
                              ),
                            ],
                          ),
                          if (canEdit)
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: busy || selected.isEmpty
                                      ? null
                                      : () => assign(tray, cells),
                                  icon: const Icon(Icons.eco_outlined),
                                  label: const Text('Add seed / plant'),
                                ),
                                TextButton.icon(onPressed:busy || !selected.any(cells.containsKey)?null:()=>transplant(tray,cells),icon:const Icon(Icons.done_all),label:const Text('Record transplant')),
                                if(selected.any((p)=>cells[p]?.isTransplanted==true))TextButton(onPressed:busy?null:()=>transplant(tray,cells,undo:true),child:const Text('Undo transplant')),
                                TextButton(
                                  onPressed:
                                      busy || !selected.any(cells.containsKey)
                                      ? null
                                      : () async {
                                          final positions =
                                              Set<TrayPosition>.of(selected);
                                          if (!await confirm(
                                            'Clear selected cells?',
                                            'Only the selected cells will be emptied.',
                                          )) {
                                            return;
                                          }
                                          if (!mounted) return;
                                          setState(() => busy = true);
                                          try {
                                            await ref
                                                .read(
                                                  seedTrayRepositoryProvider,
                                                )
                                                .clearTrayCells(
                                                  tray,
                                                  positions,
                                                );
                                            if (mounted) {
                                              setState(() => selected = {});
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
                                        },
                                  child: const Text('Clear cell contents'),
                                ),
                              ],
                            ),
                          if (error != null)
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (busy) const LinearProgressIndicator(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: SeedTrayGrid(
                              tray: tray,
                              cells: cells,
                              selected: selected,
                              onToggle: busy ? null : toggle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        );
      },
    );
  }
}

class SeedTrayGrid extends ConsumerWidget {
  const SeedTrayGrid({
    super.key,
    required this.tray,
    required this.cells,
    required this.selected,
    this.onToggle,
  });
  final SeedTray tray;
  final Map<TrayPosition, TrayAssignment> cells;
  final Set<TrayPosition> selected;
  final ValueChanged<Set<TrayPosition>>? onToggle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxonomy = ref.watch(taxonomyProvider);
    Widget header(
      String text,
      String tooltip,
      Set<TrayPosition> positions,
      String key,
    ) => SizedBox(
      width: 80,
      height: 48,
      child: Tooltip(
        message: tooltip,
        child: TextButton(
          key: ValueKey(key),
          onPressed: onToggle == null ? null : () => onToggle!(positions),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            header('All', 'Select all cells', tray.positions, 'tray-all'),
            for (var c = 1; c <= tray.columns; c++)
              header(
                'C$c',
                'Select column $c',
                tray.column(c),
                'tray-column-$c',
              ),
          ],
        ),
        for (var r = 1; r <= tray.rows; r++)
          Row(
            children: [
              header('R$r', 'Select row $r', tray.row(r), 'tray-row-$r'),
              for (var c = 1; c <= tray.columns; c++)
                Builder(
                  builder: (context) {
                    final p = TrayPosition(r, c),
                        assignment = cells[TrayPosition(r, c)],
                        active = selected.contains(TrayPosition(r, c));
                    final inherited = assignment == null
                        ? null
                        : taxonomy.taxa
                              .where((t) => t.id == assignment.taxonId)
                              .firstOrNull;
                    final appearance = inherited == null
                        ? null
                        : taxonomy.iconFor(inherited.id);
                    final label =
                        'Row $r, column $c: ${assignment == null ? 'empty' : '${assignment.kind.name}, ${assignment.label}, planted ${assignment.plantedOn ?? "not recorded"}, expected transplant ${assignment.expectedTransplantOn ?? "not set"}${assignment.isTransplanted ? ", transplanted ${assignment.transplantedOn}" : ""}'}';
                    return Semantics(
                      button: true,
                      selected: active,
                      label: label,
                      child: Tooltip(
                        message: label,
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Material(
                              color: assignment?.isTransplanted==true ? Colors.grey.shade300 : active
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: active
                                      ? OrchardBrand.forest
                                      : OrchardBrand.line,
                                  width: active ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: ValueKey('tray-cell-$r-$c'),
                                onTap: onToggle == null
                                    ? null
                                    : () => onToggle!({p}),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (assignment == null)
                                        Icon(
                                          active
                                              ? Icons.check_circle_outline
                                              : Icons.add,
                                          color: OrchardBrand.leaf,
                                          size: 22,
                                        )
                                      else
                                        Opacity(opacity:assignment.isTransplanted ? 0.45 : 1.0,child:IconPreview(
                                          size: 22,
                                          symbol:
                                              assignment.symbol ??
                                              appearance?.symbol ??
                                              PlantSymbol.unknown,
                                          customIconId:
                                              assignment.customIconId ??
                                              (assignment.symbol == null
                                                  ? appearance?.customIconId
                                                  : null),
                                        )),
                                      const SizedBox(height: 3),
                                      Text(
                                        assignment?.isTransplanted==true ? '✓ ${assignment!.label}' : assignment?.label ?? '$r:$c',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _PlantingDraft {
  const _PlantingDraft(this.assignment,this.photos);
  final TrayAssignment assignment;
  final List<SeedPacketPhoto> photos;
}

class TrayAssignmentForm extends ConsumerStatefulWidget {
  const TrayAssignmentForm({super.key, required this.count, this.initial});
  final int count;
  final TrayAssignment? initial;
  @override
  ConsumerState<TrayAssignmentForm> createState() => _AssignmentState();
}

class _AssignmentState extends ConsumerState<TrayAssignmentForm> {
  late final label = TextEditingController(text: widget.initial?.label);
  late String? taxonId = widget.initial?.taxonId;
  late TrayContentKind kind = widget.initial?.kind ?? TrayContentKind.seed;
  late bool classificationIcon =
      widget.initial?.symbol == null && widget.initial?.customIconId == null;
  late PlantSymbol symbol = widget.initial?.symbol ?? PlantSymbol.flower;
  late String? custom = widget.initial?.customIconId;
  late final days=TextEditingController(text:widget.initial?.transplantAfterDays?.toString() ?? '');
  late String? plantedOn=widget.initial==null?calendarDate(DateTime.now()):widget.initial!.plantedOn;
  late String? transplantedOn=widget.initial?.transplantedOn;
  CapturedPhoto? front,back;
  bool removeFront=false,removeBack=false,capturing=false;
  String? error;
  Future<void> capture(bool isFront,bool camera) async {
    setState(()=>capturing=true);
    try {
      final result=await ref.read(cameraProvider).capture(camera:camera);
      if(result!=null && mounted)setState((){if(isFront){front=result;removeFront=false;}else{back=result;removeBack=false;}});
    }catch(e){if(mounted)setState(()=>error='$e');}finally{if(mounted)setState(()=>capturing=false);}
  }
  String? get readyDate {
    final count=int.tryParse(days.text);
    if(plantedOn==null || count==null || count<0 || count>3650)return null;
    final p=parseCalendarDate(plantedOn!);
    return calendarDate(DateTime.utc(p.year,p.month,p.day).add(Duration(days:count)));
  }
  @override
  void dispose() {
    days.dispose();
    label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add seed / plant')),
    body: OrchardForm(
      title: 'Plant ${widget.count} cell${widget.count == 1 ? '' : 's'}',
      subtitle: 'Choose the classification and icon to display in each selected cell.',
      icon: Icons.eco_outlined,
      children: [
        SegmentedButton<TrayContentKind>(
          segments: const [
            ButtonSegment(value: TrayContentKind.seed, label: Text('Seed')),
            ButtonSegment(value: TrayContentKind.plant, label: Text('Plant')),
          ],
          selected: {kind},
          onSelectionChanged: (s) => setState(() => kind = s.single),
        ),
        ClassificationPicker(
          value: taxonId,
          onChanged: (id) => setState(() => taxonId = id),
        ),
        TextField(
          controller: label,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Cell label (optional)',
            helperText: 'Defaults to the selected classification',
          ),
        ),
        ListTile(title:const Text('Planting date'),subtitle:Text(plantedOn ?? 'Not recorded'),
          onTap:capturing?null:() async {final d=await showDatePicker(context:context,initialDate:plantedOn==null?DateTime.now():parseCalendarDate(plantedOn!),firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));if(d!=null && mounted)setState(()=>plantedOn=calendarDate(d));},
          trailing:IconButton(tooltip:'Clear planting date',icon:const Icon(Icons.clear),onPressed:capturing?null:()=>setState(()=>plantedOn=null))),
        TextField(controller:days,keyboardType:TextInputType.number,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Days until transplant (optional)',helperText:'Whole days, 0–3650')),
        if(readyDate!=null)Text('Expected transplant date: $readyDate'),
        if(widget.initial!=null)ListTile(title:const Text('Transplanted on'),subtitle:Text(transplantedOn ?? 'Not transplanted'),
          onTap:capturing?null:() async {final d=await showDatePicker(context:context,initialDate:transplantedOn==null?DateTime.now():parseCalendarDate(transplantedOn!),firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));if(d!=null && mounted)setState(()=>transplantedOn=calendarDate(d));},
          trailing:IconButton(tooltip:'Clear transplant date',icon:const Icon(Icons.clear),onPressed:()=>setState(()=>transplantedOn=null))),
        SeedPacketPhotoSlot(side:'front',draft:front,photoId:removeFront?null:widget.initial?.packetFrontId,busy:capturing,
          onCapture:(camera)=>capture(true,camera),onRemove:()=>setState((){front=null;removeFront=true;})),
        SeedPacketPhotoSlot(side:'back',draft:back,photoId:removeBack?null:widget.initial?.packetBackId,busy:capturing,
          onCapture:(camera)=>capture(false,camera),onRemove:()=>setState((){back=null;removeBack=true;})),
        if(capturing)const LinearProgressIndicator(),
        SwitchListTile(
          title: const Text('Use classification icon'),
          value: classificationIcon,
          onChanged: (v) => setState(() => classificationIcon = v),
        ),
        if (!classificationIcon)
          MapIconPicker(
            symbol: symbol,
            customIconId: custom,
            onChanged: (s, id) => setState(() {
              symbol = s!;
              custom = id;
            }),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: capturing?null:() {
            try {
              final taxonomy = ref.read(taxonomyProvider);
              if (taxonId == null || !taxonomy.isPlantIdentity(taxonId!)) {
                throw ArgumentError('Choose a Variety');
              }
              final count=days.text.trim().isEmpty?null:int.tryParse(days.text.trim());
              if(days.text.trim().isNotEmpty && count==null)throw ArgumentError('Enter whole days until transplant');
              final author=ref.read(userProvider).valueOrNull?.id;
              if((front!=null || back!=null) && author==null)throw StateError('Please sign in again');
              final frontId=front!=null?const Uuid().v4():removeFront?null:widget.initial?.packetFrontId;
              final backId=back!=null?const Uuid().v4():removeBack?null:widget.initial?.packetBackId;
              Navigator.pop(
                context,
                _PlantingDraft(TrayAssignment(
                  label: label.text.trim().isEmpty
                      ? taxonomy.byId(taxonId!).name
                      : label.text,
                  taxonId: taxonId!,
                  kind: kind,
                  assignedAt: DateTime.now().toUtc(),
                  symbol: classificationIcon ? null : symbol,
                  customIconId: classificationIcon ? null : custom,
                  plantedOn:plantedOn,transplantAfterDays:count,transplantedOn:transplantedOn,
                  packetFrontId:frontId,packetBackId:backId,
                ),[
                  if(front!=null)SeedPacketPhoto(id:frontId!,authorId:author!,image:front!.image,thumbnail:front!.thumbnail),
                  if(back!=null)SeedPacketPhoto(id:backId!,authorId:author!,image:back!.image,thumbnail:back!.thumbnail),
                ]),
              );
            } catch (e) {
              setState(() => error = '$e');
            }
          },
          child: const Text('Apply to selected cells'),
        ),
      ],
    ),
  );
}
