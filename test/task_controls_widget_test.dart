import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/application/extensions.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/ui/tasks_screen.dart';

void main() {
  Future<LocalTrialRepository> repo() async {
    SharedPreferences.setMockInitialValues({});
    return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }
  Widget wrap(LocalTrialRepository repo,Widget child,{bool editable=true})=>ProviderScope(overrides:[
    orchardRepositoryProvider.overrideWithValue(repo),
    placeProvider.overrideWith((ref) async=>repo.place),
    userProvider.overrideWith((ref)=>Stream.value(OrchardUser(repo.place.ownerId))),
    canEditOrchardProvider.overrideWithValue(editable),
    trialModeProvider.overrideWithValue(true),
  ],child:MaterialApp(home:child));
  testWidgets('checkbox, skip arrow and confirmed trash replace the task menu', (tester) async {
    final r=await repo();
    r.saveTask(OrchardTask(id:'task',propertyId:r.place.id,title:'Prune',createdAt:DateTime(2027)));
    await tester.pumpWidget(wrap(r,const Scaffold(body:TasksPane())));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<TaskStatus>),findsNothing);
    await tester.tap(find.byTooltip('Skip task'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.skipped);
    // The default Open filter hides skipped work; show every status.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All statuses').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reopen skipped task'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.open);
    await tester.tap(find.byTooltip('Mark task complete'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.completed);
    await tester.tap(find.byTooltip('Mark task incomplete'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.open);
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep task'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.open);
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Delete'));
    await tester.pumpAndSettle();
    expect(r.tasks.single.status,TaskStatus.deleted);
    expect(find.text('Prune'),findsNothing);
  });
  testWidgets('group edit appears once beside the heading, not in app bar or members', (tester) async {
    final r=await repo();
    final p=TaskPlan(id:'plan',propertyId:r.place.id,title:'Prune apples',createdAt:DateTime(2027),target:'property',dueDate:'2027-01-01');
    r.saveTaskPlan(p);
    r.saveTask(OrchardTask(id:'task',propertyId:r.place.id,title:p.title,createdAt:p.createdAt,planId:p.id,occurrenceOn:'2027-01-01',dueDate:p.dueDate));
    await tester.pumpWidget(wrap(r,TaskGroupScreen(p.id)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit task & reminders'),findsOneWidget);
    expect(find.descendant(of:find.byType(AppBar),matching:find.byType(IconButton)),findsNothing);
    final row=find.ancestor(of:find.text(p.title),matching:find.byType(Row)).first;
    expect(find.descendant(of:row,matching:find.byTooltip('Edit task & reminders')),findsOneWidget);
    expect(find.descendant(of:find.byType(TaskMemberTile),matching:find.byTooltip('Edit task & reminders')),findsNothing);
    expect(find.byType(Checkbox),findsOneWidget);
  });
  testWidgets('viewers cannot complete, skip or delete tasks', (tester) async {
    final r=await repo();
    final t=OrchardTask(id:'task',propertyId:r.place.id,title:'Prune',createdAt:DateTime(2027));
    await tester.pumpWidget(wrap(r,Scaffold(body:TaskMemberTile(t)),editable:false));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged,isNull);
    for(final tooltip in ['Skip task','Delete task']) {
      expect(tester.widget<IconButton>(find.ancestor(of:find.byTooltip(tooltip),matching:find.byType(IconButton))).onPressed,isNull);
    }
  });
}
