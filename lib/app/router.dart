import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/accounts/presentation/accounts_screen.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/home_screen.dart';
import '../features/loans/presentation/loans_screen.dart';
import '../features/loans/presentation/person_loan_screen.dart';
import '../features/more/presentation/about_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/recurring/presentation/recurring_form_screen.dart';
import '../features/recurring/presentation/recurring_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/transactions/presentation/entry_form_screen.dart';
import '../features/transactions/presentation/history_screen.dart';
import '../features/transactions/presentation/transaction_detail_screen.dart';
import '../features/voice/presentation/voice_confirm_screen.dart';
import '../features/voice/presentation/voice_entry_screen.dart';
import 'routes.dart';
import 'shell.dart';

part 'router.g.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.history, builder: (_, _) => const HistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.reports, builder: (_, _) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.more,
              builder: (_, _) => const MoreScreen(),
              routes: [
                GoRoute(path: 'budgets', builder: (_, _) => const BudgetsScreen()),
                GoRoute(path: 'recurring', builder: (_, _) => const RecurringScreen()),
                GoRoute(path: 'categories', builder: (_, _) => const CategoriesScreen()),
                GoRoute(path: 'accounts', builder: (_, _) => const AccountsScreen()),
                GoRoute(
                  path: 'loans',
                  builder: (_, _) => const LoansScreen(),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => PersonLoanScreen(personId: state.pathParameters['id']!),
                    ),
                  ],
                ),
                GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
                GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
              ],
            ),
          ]),
        ],
      ),
      // Add is an action, not a tab: it opens full-screen over the shell and
      // returns to the tab the user came from (ARCHITECTURE.md §7).
      GoRoute(
        path: Routes.add,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: EntryFormScreen(args: EntryFormArgs.fromQuery(state.uri.queryParameters)),
        ),
      ),
      GoRoute(
        path: Routes.recurringEditPath,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: RecurringFormScreen(
            ruleId: state.uri.queryParameters['id'],
            fromTransactionId: state.uri.queryParameters['from'],
          ),
        ),
      ),
      GoRoute(
        path: Routes.voice,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const VoiceEntryScreen(),
        ),
        routes: [
          GoRoute(
            path: 'confirm',
            parentNavigatorKey: _rootKey,
            // The recognised text travels as `extra`; without it there is
            // nothing to confirm, so go back to the voice screen.
            redirect: (_, state) => state.extra is String ? null : Routes.voice,
            builder: (_, state) => VoiceConfirmScreen(text: state.extra! as String),
          ),
        ],
      ),
      GoRoute(
        path: Routes.transactionPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TransactionDetailScreen(id: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
