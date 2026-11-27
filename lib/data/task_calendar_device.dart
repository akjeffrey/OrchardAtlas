import 'package:flutter/services.dart';
import '../domain/task_calendar.dart';

class DeviceTaskCalendar implements TaskCalendarRepository {
  static const _channel=MethodChannel('orchard_atlas/calendar');
  @override
  Future<List<Map<String,dynamic>>> calendars() async => [
    for(final row in await _channel.invokeListMethod<dynamic>('calendars') ?? [])
      Map<String,dynamic>.from(row as Map),
  ];
  @override
  Future<String?> selected(String scope) => _channel.invokeMethod<String>('selected',{'scope':scope});
  @override
  Future<void> select(String scope,String? calendar) => _channel.invokeMethod<void>('select',{'scope':scope,'calendar':calendar});
  @override
  Future<void> replace(String scope,List<Map<String,dynamic>> events) => _channel.invokeMethod<void>('replace',{'scope':scope,'events':events});
}
