import '../../../../l10n/l10n.dart';
import '../../domain/workspace.dart';

/// Localized label for a workspace type.
String workspaceTypeLabel(AppLocalizations l10n, WorkspaceType type) =>
    switch (type) {
      WorkspaceType.personal => l10n.workspacePersonal,
      WorkspaceType.family => l10n.workspaceFamily,
    };
