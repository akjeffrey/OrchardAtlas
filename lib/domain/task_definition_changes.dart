import 'models.dart';
import 'work.dart';
import 'task_edits.dart';
import 'landscape.dart';
import 'taxonomy.dart';

/// Updates only open current work. Recorded completions and old memberships stay.
List<OrchardTask> taskDefinitionChanges({required TaskPlan old,required TaskPlan edited,
 required List<OrchardTask> existing,required List<ManagedPlant> plants,
 required List<OrchardSection> sections,required List<CropPlanting> crops,
 required Taxonomy taxonomy,required DateTime now,
}) {
 final changes=<String,OrchardTask>{};
 final members=existing.where((t)=>belongsToTaskPlan(t,old));
 if(edited.deleted) {
   for(final t in members.where((t)=>t.status==TaskStatus.open)) {changes[t.id]=t.withStatus(TaskStatus.deleted);}
   return changes.values.toList();
 }
 final current=taskOccurrences(old,now).last;
 final next=taskOccurrences(edited,now).last;
 final targets=matchingTaskTargets(edited,plants:plants,sections:sections,crops:crops,taxonomy:taxonomy);
 for(final t in members.where((t)=>t.status==TaskStatus.open)) {
   if(taskCycleKey(t,old)==current.key) {
     final value=editOpenTask(t,title:edited.title,notes:edited.notes,dueDate:next.startsOn,
       endDate:edited.endDate==null?null:edited.repeat==RepeatSchedule.none?edited.endDate:offsetCalendarDate(next.startsOn!,taskRangeDays(edited.dueDate!,edited.endDate!)),
       eventType:t.itemId==null?null:edited.eventType,eventHarvest:edited.eventHarvest);
     changes[t.id]=taskWithMembership(value,!targets.contains(taskTargetKey(t)));
   } else if(old.scheduleId!=edited.scheduleId&&t.dueDate!=null&&current.startsOn!=null&&t.dueDate!.compareTo(current.startsOn!)>0) {
     changes[t.id]=taskWithMembership(t,true);
   }
 }
 final updated=[for(final t in existing) changes[t.id]??t];
 for(final t in expandPlans(plans:[edited],existing:updated,plants:plants,sections:sections,crops:crops,taxonomy:taxonomy,now:now)) {changes[t.id]=t;}
 return changes.values.toList();
}
