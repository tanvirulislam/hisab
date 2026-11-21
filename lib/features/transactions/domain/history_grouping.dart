import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import 'ledger_entry.dart';

/// Totals over a set of entries using the reporting rules: transfers are
/// excluded (rule 4), and refunds reduce expense instead of counting as
/// income (rule 7, D5).
class EntryTotals {
  const EntryTotals({required this.income, required this.expense});

  static const zero = EntryTotals(income: Money.zero, expense: Money.zero);

  final Money income;

  /// Net expense: expenses − refunds.
  final Money expense;

  Money get net => income - expense;

  @override
  bool operator ==(Object other) =>
      other is EntryTotals && other.income == income && other.expense == expense;

  @override
  int get hashCode => Object.hash(income, expense);

  @override
  String toString() => 'EntryTotals(income: $income, expense: $expense)';

  static EntryTotals of(Iterable<LedgerEntry> entries) {
    var income = Money.zero;
    var expense = Money.zero;
    for (final e in entries) {
      switch (e.kind) {
        case EntryKind.income:
          income += e.amount;
        case EntryKind.expense:
          expense += e.amount;
        case EntryKind.refund:
          expense -= e.amount;
        case EntryKind.transferOut || EntryKind.transferIn:
          break;
      }
    }
    return EntryTotals(income: income, expense: expense);
  }
}

class DaySection {
  const DaySection({required this.date, required this.items, required this.totals});

  final LocalDate date;
  final List<HistoryItem> items;
  final EntryTotals totals;
}

/// Groups items (already sorted newest first) into day sections. History
/// pages always contain complete days, so these totals are exact.
List<DaySection> groupByDay(List<HistoryItem> items) {
  final sections = <DaySection>[];
  var start = 0;
  for (var i = 1; i <= items.length; i++) {
    if (i == items.length || items[i].entry.date != items[start].entry.date) {
      final dayItems = items.sublist(start, i);
      sections.add(DaySection(
        date: items[start].entry.date,
        items: dayItems,
        totals: EntryTotals.of(dayItems.map((it) => it.entry)),
      ));
      start = i;
    }
  }
  return sections;
}
