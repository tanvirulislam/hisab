import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace.freezed.dart';

/// Only Personal exists since the Family workspace was removed (D14).
enum WorkspaceType {
  personal('personal');

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
