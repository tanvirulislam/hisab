import '../../../core/constants/default_categories.dart';
import '../../categories/domain/category.dart';
import 'text_tokens.dart';
import 'voice_keywords.dart';

/// One keyword that points to a category.
class LexiconEntry {
  const LexiconEntry({
    required this.phrase,
    required this.weight,
    required this.type,
    required this.categoryId,
    this.subcategoryId,
  });

  /// Matching keys of the keyword's words.
  final List<String> phrase;

  /// 3 = specific item word, 1 = context word (see [voiceKeywords]).
  final int weight;
  final CategoryType type;

  /// Top-level category.
  final String categoryId;
  final String? subcategoryId;
}

/// Keywords for the categories one workspace can use, built from the live
/// category list so archived categories are never proposed and user
/// categories are found by name.
class CategoryLexicon {
  CategoryLexicon._(this.entries, this._fallback);

  final List<LexiconEntry> entries;
  final Map<CategoryType, String?> _fallback;

  static const int strong = 3;
  static const int weak = 1;

  /// "Others" / "Other Income": used when nothing matches.
  String? fallbackFor(CategoryType type) => _fallback[type];

  /// [categories]: the active categories (both types) of one workspace.
  factory CategoryLexicon.build(List<Category> categories) {
    final active = categories.where((c) => c.isActive).toList();
    final byId = {for (final c in active) c.id: c};
    final entries = <LexiconEntry>[];

    void add(Category c, String keyword, int weight) {
      final keys = TextTokens.keysOf(keyword).where((k) => k != ',').toList();
      if (keys.isEmpty) return;
      final parentId = c.parentId;
      if (parentId != null && !byId.containsKey(parentId)) return; // parent archived
      entries.add(LexiconEntry(
        phrase: keys,
        weight: weight,
        type: c.type,
        categoryId: parentId ?? c.id,
        subcategoryId: parentId == null ? null : c.id,
      ));
    }

    for (final c in active) {
      final words = c.systemKey == null ? null : voiceKeywords[c.systemKey];
      for (final w in words ?? const <String>[]) {
        w.startsWith('~') ? add(c, w.substring(1), weak) : add(c, w, strong);
      }
      // Names in both languages, plus the stored name (user categories). A
      // parent's name is broad ("Family"), so it only gives context.
      final hasChildren = active.any((x) => x.parentId == c.id);
      for (final name in {c.name, c.displayName('bn'), c.displayName('en')}) {
        add(c, name, hasChildren ? weak : strong);
      }
    }

    String? fallback(String key, CategoryType type) =>
        active.where((c) => c.systemKey == key).firstOrNull?.id ??
        active.where((c) => c.type == type && !c.isSubcategory).firstOrNull?.id;

    return CategoryLexicon._(entries, {
      CategoryType.expense: fallback(SystemCategoryKeys.otherExpense, CategoryType.expense),
      CategoryType.income: fallback(SystemCategoryKeys.otherIncome, CategoryType.income),
    });
  }
}
