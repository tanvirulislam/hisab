import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../l10n/l10n.dart';
import 'backup_providers.dart';

/// Fresh install with no user data: offer to bring the data back from Drive
/// (D22). Shown once per install; gone once dismissed, used or data exists.
class RestoreOfferCard extends ConsumerWidget {
  const RestoreOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(restoreOfferProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final offer = ref.read(restoreOfferProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cloud_download_outlined, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(child: Text(l.restoreOfferTitle, style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 36, right: 8),
                child: Text(l.restoreOfferBody, style: theme.textTheme.bodyMedium),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton(onPressed: offer.dismiss, child: Text(l.restoreOfferDismiss)),
                  FilledButton.tonal(
                    onPressed: () {
                      offer.dismiss();
                      context.push(Routes.backup);
                    },
                    child: Text(l.restoreOfferAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
