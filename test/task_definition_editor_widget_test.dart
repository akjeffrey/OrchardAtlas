import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/work.dart';
import 'package:orchard_atlas/domain/taxonomy.dart';
import 'package:orchard_atlas/ui/task_editor.dart';

void main() {
 Future<LocalTrialRepository> setup() async {
  SharedPreferences.setMockInitialValues({});
  return LocalTrialRepository.open(await SharedPreferences.getInstance());
 }
 Widget wrap(LocalTrialRepository r,TaskPlan p)=>ProviderScope(overrides:[
  orchardRepositoryProvider.overrideWithValue(r),authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
  placeProvider.overrideWith((ref) async=>r.place),trialModeProvider.overrideWithValue(true),
 ],child:MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(
  onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>TaskEditor(plan:p))),child:const Text('Open editor'),
 )))));
 testWidgets('repeating start date opens its picker and whole-task deletion is confirmed',(tester) async {
  final r=await setup();
  final p=TaskPlan(id:'plan',propertyId:r.place.id,title:'Water',createdAt:DateTime.now(),target:'property',dueDate:calendarDate(DateTime.now()),repeat:RepeatSchedule.weekly);
  r.saveTaskPlan(p);
  final tasks=expandPlans(plans:[p],existing:[],plants:[],sections:[],crops:[],taxonomy:starterTaxonomy,now:DateTime.now());
  for(final t in tasks) {r.saveTask(t);}
  await tester.pumpWidget(wrap(r,p));await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Start date'),150,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.text('Start date'));await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog),findsOneWidget);
  await tester.tap(find.text('OK'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.widgetWithText(OutlinedButton,'Delete entire task'),180,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.widgetWithText(OutlinedButton,'Delete entire task'));await tester.pumpAndSettle();
  await tester.tap(find.text('Keep task'));await tester.pumpAndSettle();
  expect((await tester.runAsync(()=>r.watchTaskPlans(r.place.id).first))!.single.deleted,isFalse);
  await tester.tap(find.widgetWithText(OutlinedButton,'Delete entire task'));await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton,'Delete entire task'));await tester.pumpAndSettle();
  expect(find.text('Open editor'),findsOneWidget);
  expect((await tester.runAsync(()=>r.watchTaskPlans(r.place.id).first))!.single.deleted,isTrue);
  expect(r.tasks.every((t)=>t.status==TaskStatus.deleted),isTrue);
 });
 testWidgets('individual plant overrides can be removed and saved from task editing',(tester) async {
  final r=await setup();
  final taxon=starterTaxonomy.taxa[2].id;
  final plant=ManagedPlant(id:'plant',propertyId:r.place.id,name:'Apple 1',taxonId:taxon,location:Coordinates(1,2),createdAt:DateTime.now());r.savePlant(plant);
  final p=TaskPlan(id:'plan',propertyId:r.place.id,title:'Prune',createdAt:DateTime.now(),target:'plants',dueDate:calendarDate(DateTime.now()));r.saveTaskPlan(p);
  for(final t in expandPlans(plans:[p],existing:[],plants:[plant],sections:[],crops:[],taxonomy:starterTaxonomy,now:DateTime.now())) {r.saveTask(t);}
  await tester.pumpWidget(wrap(r,p));await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(const ValueKey('task-target-p:plant')),140,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.byKey(const ValueKey('task-target-p:plant')));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Save task changes'),200,scrollable:find.byType(Scrollable).first);
  await tester.tap(find.text('Save task changes'));await tester.pumpAndSettle();
  expect(find.text('Open editor'),findsOneWidget);
  expect(r.tasks.single.membershipExcluded,isTrue);
  final saved=(await tester.runAsync(()=>r.watchTaskPlans(r.place.id).first))!.single;
  expect(saved.excludedTargets,['p:plant']);
 });
}
