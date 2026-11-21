import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../../core/services/local_prefs.dart';
import '../data/drift_workspace_repository.dart';
import '../domain/workspace.dart';
import '../domain/workspace_repository.dart';

part 'workspace_providers.g.dart';

@Riverpod(keepAlive: true)
WorkspaceRepository workspaceRepository(Ref ref) =>
    DriftWorkspaceRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
Stream<List<Workspace>> workspaces(Ref ref) =>
    ref.watch(workspaceRepositoryProvider).watchWorkspaces();

/// The scope chosen in the workspace switcher, shared by Home, History and
/// Reports, and remembered across restarts.
@Riverpod(keepAlive: true)
class ActiveWorkspaceScope extends _$ActiveWorkspaceScope {
  @override
  WorkspaceScope build() => WorkspaceScope.parse(
    ref.watch(localPrefsProvider).getString(LocalPrefKeys.workspaceScope),
  );

  Future<void> select(WorkspaceScope scope) async {
    if (state == scope) return;
    state = scope;
    await ref
        .read(localPrefsProvider)
        .setString(LocalPrefKeys.workspaceScope, scope.name);
  }
}

/// Workspace IDs covered by the active scope.
@Riverpod(keepAlive: true)
Future<List<String>> activeWorkspaceIds(Ref ref) async {
  final scope = ref.watch(activeWorkspaceScopeProvider);
  final all = await ref.watch(workspacesProvider.future);
  return scope.resolveIds(all);
}
