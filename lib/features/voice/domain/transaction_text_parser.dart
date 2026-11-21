import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../transactions/domain/ledger_entry.dart';
import 'category_lexicon.dart';

/// One transaction proposed from spoken text. Nothing is saved until the
/// user confirms it (§9.1).
class ParsedProposal {
  const ParsedProposal({
    required this.type,
    required this.amount,
    required this.categoryId,
    this.subcategoryId,
    required this.date,
    this.description,
    required this.confidence,
    required this.sourceText,
  });

  final EntryType type;

  /// NULL when no amount was heard; the user must enter one.
  final Money? amount;

  /// Top-level category; the fallback "Others" when nothing matched.
  final String? categoryId;
  final String? subcategoryId;
  final LocalDate date;
  final String? description;

  /// 0..1. Below [reviewThreshold] the confirmation screen asks the user to
  /// check the item.
  final double confidence;

  /// The part of the sentence this item came from.
  final String sourceText;

  static const double reviewThreshold = 0.8;

  bool get needsReview => confidence < reviewThreshold || amount == null;
}

class ParseContext {
  const ParseContext({required this.today, required this.lexicon});

  final LocalDate today;
  final CategoryLexicon lexicon;
}

/// Turns recognised speech into proposals (D12). The rule-based parser is
/// the MVP; an AI parser can replace it by implementing this interface.
abstract interface class TransactionTextParser {
  List<ParsedProposal> parse(String text, ParseContext context);
}
