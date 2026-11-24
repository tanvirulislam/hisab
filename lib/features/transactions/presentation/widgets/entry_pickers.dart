import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/local_date.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../l10n/l10n.dart';
import '../../../accounts/domain/account.dart';
import '../../../accounts/presentation/accounts_screen.dart';
import '../../../categories/domain/category.dart';
import '../../../settings/presentation/app_formats.dart';

/// Icon grid of top-level categories (§8.1: visual category selection).
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.nodes,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryNode> nodes;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final perRow = (constraints.maxWidth / 84).floor().clamp(3, 6);
      final width = constraints.maxWidth / perRow;
      return Wrap(
        children: [
          for (final n in nodes)
            SizedBox(
              width: width,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(n.category.id),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: n.category.id == selectedId ? scheme.secondaryContainer : null,
                    border: Border.all(
                      color: n.category.id == selectedId ? scheme.secondary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      CategoryAvatar(iconKey: n.category.iconKey, color: Color(n.category.color)),
                      const SizedBox(height: 4),
                      Text(
                        n.category.displayName(lang),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Optional subcategory chips for the selected category.
class SubcategoryChips extends StatelessWidget {
  const SubcategoryChips({
    super.key,
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Category> children;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text(context.l10n.noneOption),
          selected: selectedId == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final c in children)
          ChoiceChip(
            label: Text(c.displayName(lang)),
            selected: c.id == selectedId,
            onSelected: (_) => onSelected(c.id),
          ),
      ],
    );
  }
}

class AccountChips extends StatelessWidget {
  const AccountChips({
    super.key,
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final a in accounts)
        ChoiceChip(
          avatar: Icon(_accountIcon(a.type), size: 18),
          label: Text(a.name),
          selected: a.id == selectedId,
          onSelected: (_) => onSelected(a.id),
        ),
    ],
  );
}

IconData _accountIcon(AccountType t) => switch (t) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.bkash || AccountType.nagad => Icons.phone_iphone,
  AccountType.savings => Icons.savings_outlined,
  AccountType.other => Icons.account_balance_wallet_outlined,
};

/// Account dropdown (transfers).
class AccountDropdown extends StatelessWidget {
  const AccountDropdown({
    super.key,
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DropdownButtonFormField<String>(
      initialValue: accounts.any((a) => a.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Text(
              '${a.name} (${accountTypeLabel(l, a.type)})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Date and time chips (§6.2: transaction date and time; default now).
class DateTimeChips extends ConsumerWidget {
  const DateTimeChips({
    super.key,
    required this.date,
    required this.time,
    required this.onDate,
    required this.onTime,
  });

  final LocalDate date;
  final TimeOfDay time;
  final ValueChanged<LocalDate> onDate;
  final ValueChanged<TimeOfDay> onTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(appFormatsProvider);
    final l = context.l10n;
    final dateLabel = f.isToday(date)
        ? l.today
        : f.isYesterday(date)
            ? l.yesterday
            : f.dateLong(date);
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return Wrap(
      spacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.calendar_today, size: 18),
          label: Text(dateLabel),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date.toDateTime(),
              firstDate: DateTime(2000),
              lastDate: DateTime(f.today.year + 1, 12, 31),
            );
            if (picked != null) onDate(LocalDate.fromDateTime(picked));
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text(f.time(dt)),
          onPressed: () async {
            final picked = await showTimePicker(context: context, initialTime: time);
            if (picked != null) onTime(picked);
          },
        ),
      ],
    );
  }
}

class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key, this.errorText});

  final String text;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Text(text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
          if (errorText != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(errorText!,
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error)),
            ),
          ],
        ],
      ),
    );
  }
}
