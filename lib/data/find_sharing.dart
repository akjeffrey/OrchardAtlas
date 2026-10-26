import 'package:flutter/services.dart';

import '../domain/find_sharing.dart';

class DeviceFindSharing implements FindSharingRepository {
  static const _channel = MethodChannel('orchard_atlas/share');
  @override
  Future<void> share(String text) async {
    await _channel.invokeMethod<void>('shareText', {'text': text});
  }
}
