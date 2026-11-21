import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../l10n/l10n.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreAbout)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.account_balance_wallet, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            l10n.appTitle,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Text(
              snap.hasData ? l10n.aboutVersion(snap.data!.version) : '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.aboutDescription, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
