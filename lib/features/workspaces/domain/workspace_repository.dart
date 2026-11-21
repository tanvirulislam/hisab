import 'workspace.dart';

abstract interface class WorkspaceRepository {
  /// Active workspaces, Personal first.
  Stream<List<Workspace>> watchWorkspaces();
}
