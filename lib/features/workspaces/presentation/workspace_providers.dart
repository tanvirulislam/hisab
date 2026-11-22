import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../data/drift_workspace_repository.dart';
import '../domain/workspace.dart';
import '../domain/workspace_repository.dart';

part 'workspace_providers.g.dart';

@Riverpod(keepAlive: true)
WorkspaceRepository workspaceRepository(Ref ref) =>
    DriftWorkspaceRepository(ref.watch(appDatabaseProvider));

/// Workspaces the app shows: only Personal (D14). The Family workspace stays
/// in the database (seeded, never written to) so the feature can return
/// without a migration; every picker and label hides itself when this list
/// has a single entry.
@Riverpod(keepAlive: true)
Stream<List<Workspace>> workspaces(Ref ref) => ref
    .watch(workspaceRepositoryProvider)
    .watchWorkspaces()
    .map((all) => [for (final w in all) if (w.type == WorkspaceType.personal) w]);

/// The active scope. Fixed to Personal since the switcher was removed (D14).
@Riverpod(keepAlive: true)
class ActiveWorkspaceScope extends _$ActiveWorkspaceScope {
  @override
  WorkspaceScope build() => WorkspaceScope.personal;
}

/// Workspace IDs covered by the active scope.
@Riverpod(keepAlive: true)
Future<List<String>> activeWorkspaceIds(Ref ref) async {
  final scope = ref.watch(activeWorkspaceScopeProvider);
  final all = await ref.watch(workspacesProvider.future);
  return scope.resolveIds(all);
}
