import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../data/speech_input.dart';
import '../domain/category_lexicon.dart';
import '../domain/rule_based_parser.dart';
import '../domain/transaction_text_parser.dart';

part 'voice_providers.g.dart';

/// The device recognizer. Tests override this with a scripted fake.
@Riverpod(keepAlive: true)
SpeechInput speechInput(Ref ref) => DeviceSpeechInput();

/// Swappable parser (D12): an AI parser would be provided here.
@Riverpod(keepAlive: true)
TransactionTextParser transactionTextParser(Ref ref) => const RuleBasedBnEnParser();

/// Keywords for the active categories of one workspace.
@riverpod
Future<CategoryLexicon> voiceLexicon(Ref ref, String workspaceId) async {
  final expense = await ref.watch(workspaceCategoryTreeProvider(workspaceId, CategoryType.expense).future);
  final income = await ref.watch(workspaceCategoryTreeProvider(workspaceId, CategoryType.income).future);
  return CategoryLexicon.build([
    for (final n in [...expense, ...income]) ...[n.category, ...n.children],
  ]);
}
