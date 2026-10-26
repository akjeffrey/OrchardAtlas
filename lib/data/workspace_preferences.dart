import 'package:shared_preferences/shared_preferences.dart';

import '../domain/workspaces.dart';

class DeviceWorkspacePreferences implements WorkspacePreferences {
  DeviceWorkspacePreferences(this.preferences);
  final SharedPreferences preferences;
  static String key(String userId) => 'workspace-mode:$userId';
  @override
  Future<WorkspaceMode> loadMode(String userId) async =>
      preferences.getString(key(userId)) == WorkspaceMode.foraging.name
      ? WorkspaceMode.foraging
      : WorkspaceMode.orchard;
  @override
  Future<void> saveMode(String userId, WorkspaceMode mode) async {
    if (!await preferences.setString(key(userId), mode.name)) {
      throw StateError('Could not remember mode on this device');
    }
  }
}
