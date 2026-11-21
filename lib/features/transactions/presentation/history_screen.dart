import 'package:flutter/material.dart';

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';

/// Transaction history. The date-grouped list, filters and search arrive
/// in Phase 2.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ScopedPage(
      title: l10n.navHistory,
      body: EmptyState(
        icon: Icons.history,
        title: l10n.historyEmptyTitle,
        message: l10n.historyEmptyMessage,
      ),
    );
  }
}
