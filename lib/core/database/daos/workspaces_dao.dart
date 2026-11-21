import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'workspaces_dao.g.dart';

@DriftAccessor(tables: [Workspaces])
class WorkspacesDao extends DatabaseAccessor<AppDatabase>
    with _$WorkspacesDaoMixin {
  WorkspacesDao(super.attachedDatabase);

  /// Active workspaces, Personal first.
  Stream<List<WorkspaceRow>> watchAll() {
    final query = select(workspaces)
      ..where((w) => w.deletedAt.isNull())
      ..orderBy([
        (w) => OrderingTerm(
          expression: CaseWhenExpression<int>(
            cases: [CaseWhen(w.type.equals('personal'), then: const Constant(0))],
            orElse: const Constant(1),
          ),
        ),
        (w) => OrderingTerm(expression: w.createdAt),
      ]);
    return query.watch();
  }

  Future<WorkspaceRow?> findById(String id) =>
      (select(workspaces)..where((w) => w.id.equals(id))).getSingleOrNull();

  Future<List<WorkspaceRow>> getAll() => select(workspaces).get();
}
