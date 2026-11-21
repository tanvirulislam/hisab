import '../../../core/database/app_database.dart';
import '../domain/workspace.dart';
import '../domain/workspace_repository.dart';

class DriftWorkspaceRepository implements WorkspaceRepository {
  DriftWorkspaceRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Workspace>> watchWorkspaces() =>
      _db.workspacesDao.watchAll().map((rows) => rows.map(_toDomain).toList());

  static Workspace _toDomain(WorkspaceRow row) => Workspace(
    id: row.id,
    name: row.name,
    type: WorkspaceType.fromDb(row.type),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );
}
