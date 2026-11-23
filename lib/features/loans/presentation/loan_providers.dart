import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../../core/utils/money.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_loan_repository.dart';
import '../domain/loan.dart';
import '../domain/loan_repository.dart';

part 'loan_providers.g.dart';

@Riverpod(keepAlive: true)
LoanRepository loanRepository(Ref ref) =>
    DriftLoanRepository(ref.watch(appDatabaseProvider));

/// Everyone with an open or settled loan, for the active workspace scope.
@riverpod
Stream<List<PersonLoanSummary>> loanSummaries(Ref ref) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(loanRepositoryProvider).watchSummaries(ids);
}

/// Total still owed to me / by me. Derived from [loanSummariesProvider].
@riverpod
LoanTotals loanTotals(Ref ref) {
  final list = ref.watch(loanSummariesProvider).value ?? const <PersonLoanSummary>[];
  return LoanTotals(
    owedToMe: Money.sum(list.map((s) => s.owedToMe)),
    iOwe: Money.sum(list.map((s) => s.iOwe)),
  );
}

@riverpod
Stream<Person?> loanPerson(Ref ref, String personId) =>
    ref.watch(loanRepositoryProvider).watchPerson(personId);

@riverpod
Stream<List<LoanEntry>> loanEntries(Ref ref, String personId) =>
    ref.watch(loanRepositoryProvider).watchEntries(personId);
