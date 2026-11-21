import 'package:flutter/material.dart';

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';

/// Quick transaction entry. The real form arrives in Phase 2.
class AddTransactionScreen extends StatelessWidget {
  const AddTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navAdd),
        leading: const CloseButton(),
      ),
      body: EmptyState(
        icon: Icons.edit_note,
        title: l10n.addUnavailableTitle,
        message: l10n.addUnavailableMessage,
      ),
    );
  }
}
