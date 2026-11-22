import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../data/drift_workspace_repository.dart';
import '../domain/workspace.dart';
import '../domain/workspace_repository.dart';

part 'workspace_providers.g.dart';

@Riverpod(keepAlive: true)
WorkspaceRepository workspaceRepository(Ref ref) =>
    DriftWorkspaceRepository(ref.watch(appDatabaseProvider));

/// The workspaces (only Personal since D14).
@Riverpod(keepAlive: true)
Stream<List<Workspace>> workspaces(Ref ref) =>
    ref.watch(workspaceRepositoryProvider).watchWorkspaces();

/// Workspace IDs every query is filtered with.
@Riverpod(keepAlive: true)
Future<List<String>> activeWorkspaceIds(Ref ref) async {
  final all = await ref.watch(workspacesProvider.future);
  return [for (final w in all) w.id];
}
