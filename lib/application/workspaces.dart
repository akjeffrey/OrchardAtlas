import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/workspaces.dart';
import 'providers.dart';

final workspacePreferencesProvider = Provider<WorkspacePreferences>(
  (ref) => MemoryWorkspacePreferences(),
);
final workspaceModeProvider =
    StateNotifierProvider<WorkspaceModeController, AsyncValue<WorkspaceMode>>(
      (ref) => WorkspaceModeController(
        ref.watch(workspacePreferencesProvider),
        ref.watch(userProvider).valueOrNull?.id ?? 'signed-out',
      ),
    );

class WorkspaceModeController extends StateNotifier<AsyncValue<WorkspaceMode>> {
  WorkspaceModeController(this.repository, this.userId)
    : super(const AsyncLoading()) {
    _ready = _load();
  }
  final WorkspacePreferences repository;
  final String userId;
  late final Future<void> _ready;
  Future<void> _load() async {
    try {
      final mode = await repository.loadMode(userId);
      if (mounted) state = AsyncData(mode);
    } catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    }
  }

  Future<void> select(WorkspaceMode mode) async {
    await _ready;
    await repository.saveMode(userId, mode);
    if (mounted) state = AsyncData(mode);
  }
}
