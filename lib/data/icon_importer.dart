import 'package:flutter/services.dart';

import '../domain/map_icons.dart';

class DeviceIconImporter implements IconImporter {
  static const channel = MethodChannel('orchard_atlas/backup');
  @override
  Future<Uint8List?> importPng() async {
    final bytes = await channel.invokeMethod<Uint8List>('importIcon');
    if (bytes != null) MapIcon.validatePng(bytes);
    return bytes;
  }
}
