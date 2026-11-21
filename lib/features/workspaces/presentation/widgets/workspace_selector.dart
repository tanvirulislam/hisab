import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/workspace.dart';
import '../workspace_providers.dart';

/// Personal / Family / Combined switch. Changing it updates every
/// scope-aware screen.
class WorkspaceSelector extends ConsumerWidget {
  const WorkspaceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(activeWorkspaceScopeProvider);
    final l10n = context.l10n;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<WorkspaceScope>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: WorkspaceScope.personal,
            label: Text(l10n.workspacePersonal),
            icon: const Icon(Icons.person_outline),
          ),
          ButtonSegment(
            value: WorkspaceScope.family,
            label: Text(l10n.workspaceFamily),
            icon: const Icon(Icons.family_restroom),
          ),
          ButtonSegment(
            value: WorkspaceScope.combined,
            label: Text(l10n.workspaceCombined),
            icon: const Icon(Icons.join_inner),
          ),
        ],
        selected: {scope},
        onSelectionChanged: (s) =>
            ref.read(activeWorkspaceScopeProvider.notifier).select(s.first),
      ),
    );
  }
}

/// Localized label for a workspace type.
String workspaceTypeLabel(AppLocalizations l10n, WorkspaceType type) =>
    switch (type) {
      WorkspaceType.personal => l10n.workspacePersonal,
      WorkspaceType.family => l10n.workspaceFamily,
    };
