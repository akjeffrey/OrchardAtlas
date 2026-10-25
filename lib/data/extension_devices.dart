import 'package:flutter/services.dart';

import '../domain/extensions.dart';

class DeviceCamera implements CameraRepository {
  static const _channel = MethodChannel('orchard_atlas/photos');
  @override
  Future<CapturedPhoto?> capture({required bool camera}) async {
    final d = await _channel.invokeMapMethod<String, dynamic>('capture', {
      'camera': camera,
    });
    if (d == null) return null;
    return CapturedPhoto(d['image'] as Uint8List, d['thumbnail'] as Uint8List);
  }
}

class DeviceReminders implements ReminderScheduler {
  static const _channel = MethodChannel('orchard_atlas/reminders');
  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('permission') ?? false;
  @override
  Future<void> replace(
    String orchard,
    List<Map<String, dynamic>> notifications,
  ) async {
    await _channel.invokeMethod<void>('replace', {
      'orchard': orchard,
      'notifications': notifications,
    });
  }
}
