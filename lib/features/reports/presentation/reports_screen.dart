import 'package:flutter/material.dart';

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';

/// Reports. Daily, weekly, monthly and category reports arrive in Phase 3.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ScopedPage(
      title: l10n.navReports,
      body: EmptyState(
        icon: Icons.bar_chart,
        title: l10n.reportsEmptyTitle,
        message: l10n.reportsEmptyMessage,
      ),
    );
  }
}
