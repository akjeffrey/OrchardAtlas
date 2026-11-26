import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orchard_atlas/application/providers.dart';
import 'package:orchard_atlas/data/local_trial_repository.dart';
import 'package:orchard_atlas/domain/models.dart';
import 'package:orchard_atlas/domain/seed_trays.dart';
import 'package:orchard_atlas/ui/seed_trays_screen.dart';
import 'package:orchard_atlas/ui/icon_picker.dart';

void main(){
  Future<LocalTrialRepository> repository()async{
    SharedPreferences.setMockInitialValues({});return LocalTrialRepository.open(await SharedPreferences.getInstance());
  }
  Widget wrap(LocalTrialRepository repo,Widget child)=>ProviderScope(overrides:[
    orchardRepositoryProvider.overrideWithValue(repo),authRepositoryProvider.overrideWithValue(TrialAuthRepository()),
    placeProvider.overrideWith((ref)async=>repo.place),
  ],child:MaterialApp(home:child));
  Finder dropdown(String name)=>find.byWidgetPredicate((w)=>w is DropdownButtonFormField<String> && w.decoration.labelText==name);
  Future<void> choose(WidgetTester t,String label,String choice)async{
    await t.scrollUntilVisible(dropdown(label),140,scrollable:find.byType(Scrollable).first);
    await t.tap(dropdown(label));await t.pumpAndSettle();await t.tap(find.text(choice).last);await t.pumpAndSettle();
  }
  testWidgets('tray grid selects cells/rows/columns and displays an icon for every assigned cell',(tester)async{
    final repo=await repository();final tray=SeedTray(id:'tray',propertyId:repo.place.id,name:'Windowsill',rows:2,columns:3,createdAt:DateTime(2026));
    await repo.createSeedTray(tray);
    await tester.pumpWidget(wrap(repo,SeedTrayDetail(tray.id)));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tray-cell-1-1')),findsOneWidget);expect(find.byKey(const ValueKey('tray-cell-2-3')),findsOneWidget);
    expect(find.byKey(const ValueKey('tray-cell-3-1')),findsNothing);
    await tester.tap(find.byKey(const ValueKey('tray-row-1')));await tester.pumpAndSettle();expect(find.text('3 selected'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tray-column-2')));await tester.pumpAndSettle();expect(find.text('4 selected'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tray-cell-2-3')));await tester.pumpAndSettle();expect(find.text('5 selected'),findsOneWidget);
    await tester.tap(find.text('Add seed / plant'));await tester.pumpAndSettle();
    await choose(tester,'Group','Fruit trees');await choose(tester,'Type','Apple (Malus)');await choose(tester,'Variety','Domestic apple');
    await tester.scrollUntilVisible(find.text('Apply to selected cells'),180,scrollable:find.byType(Scrollable).first);
    await tester.tap(find.text('Apply to selected cells'));await tester.pumpAndSettle();
    expect(find.text('0 selected'),findsOneWidget);expect(find.byType(IconPreview),findsNWidgets(5));
    final saved=await tester.runAsync(()=>repo.watchTrayCells(tray.propertyId,tray.id).first);
    expect(saved,hasLength(5));expect(saved!.containsKey(TrayPosition(2,1)),isFalse);expect(saved.values.every((a)=>a.label=='Domestic apple'),isTrue);
    await tester.tap(find.byTooltip('Rename tray'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField,'Tray name'),'Greenhouse tray');await tester.tap(find.text('Save name'));await tester.pumpAndSettle();
    expect(find.text('Greenhouse tray'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  },timeout:const Timeout(Duration(seconds:30)));
  testWidgets('new tray dimensions produce the requested grid and malformed counts show validation',(tester)async{
    final repo=await repository();await tester.pumpWidget(wrap(repo,const SeedTrayForm()));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'Tray name'),'Spring seeds');
    await tester.enterText(find.widgetWithText(TextField,'Rows'),'0');await tester.tap(find.text('Create tray'));await tester.pumpAndSettle();
    expect(find.textContaining('Use 1–24'),findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField,'Rows'),'2');await tester.enterText(find.widgetWithText(TextField,'Columns'),'3');
    await tester.tap(find.text('Create tray'));await tester.pumpAndSettle();
    expect(find.byType(SeedTrayGrid),findsOneWidget);expect(find.text('2 rows × 3 columns · 0/6 occupied'),findsOneWidget);
    final trays=await tester.runAsync(()=>repo.watchSeedTrays(repo.place.id).first);expect(trays!.single.name,'Spring seeds');
    await tester.pumpWidget(const SizedBox.shrink());
  },timeout:const Timeout(Duration(seconds:30)));
}
