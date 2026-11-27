import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orchard_atlas/ui/task_schedule_fields.dart';

void main() {
  testWidgets('multiple day and week reminders can be added and individually removed', (tester) async {
    var offsets=<int>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SingleChildScrollView(child:TaskScheduleFields(
      start:'2027-03-28',end:null,offsets:offsets,onDates:(_,_) {},onReminders:(v)=>setState(()=>offsets=v),
    ))))));
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'3');
    await tester.tap(find.widgetWithText(FilledButton,'Add reminder'));
    await tester.pumpAndSettle();
    expect(offsets,[3]);
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeks').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'2');
    await tester.tap(find.widgetWithText(FilledButton,'Add reminder'));
    await tester.pumpAndSettle();
    expect(offsets,[3,14]);
    await tester.tap(find.byTooltip('Remove reminder').first);
    await tester.pumpAndSettle();
    expect(offsets,[14]);
    expect(find.text('2 week(s) before start'),findsOneWidget);
  });
}
