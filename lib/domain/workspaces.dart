/// A view choice; selecting a mode never changes record ownership or identity.
enum WorkspaceMode { orchard, foraging }

abstract interface class WorkspacePreferences {
  Future<WorkspaceMode> loadMode(String userId);
  Future<void> saveMode(String userId, WorkspaceMode mode);
}

/// Default for embedded views/tests; production overrides with device storage.
class MemoryWorkspacePreferences implements WorkspacePreferences {
  final _modes = <String, WorkspaceMode>{};
  @override
  Future<WorkspaceMode> loadMode(String userId) async =>
      _modes[userId] ?? WorkspaceMode.orchard;
  @override
  Future<void> saveMode(String userId, WorkspaceMode mode) async {
    _modes[userId] = mode;
  }
}
