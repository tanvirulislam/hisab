import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace.freezed.dart';

enum WorkspaceType {
  personal('personal'),
  family('family');

  const WorkspaceType(this.dbValue);

  final String dbValue;

  static WorkspaceType fromDb(String value) =>
      values.firstWhere((t) => t.dbValue == value,
          orElse: () => throw ArgumentError('Unknown workspace type: $value'));
}

@freezed
abstract class Workspace with _$Workspace {
  const factory Workspace({
    required String id,
    required String name,
    required WorkspaceType type,
    required DateTime createdAt,
  }) = _Workspace;
}

/// What the dashboard, history and reports are showing (D9).
///
/// [combined] is read-only. Entry forms always need a real workspace.
enum WorkspaceScope {
  personal,
  family,
  combined;

  bool includes(WorkspaceType type) => switch (this) {
    WorkspaceScope.personal => type == WorkspaceType.personal,
    WorkspaceScope.family => type == WorkspaceType.family,
    WorkspaceScope.combined => true,
  };

  /// IDs of the workspaces this scope covers. Every scoped query filters
  /// with these, so Personal and Family data never mix.
  List<String> resolveIds(Iterable<Workspace> workspaces) => [
    for (final w in workspaces)
      if (includes(w.type)) w.id,
  ];

  static WorkspaceScope parse(String? value) => values.firstWhere(
    (s) => s.name == value,
    orElse: () => WorkspaceScope.personal,
  );
}
