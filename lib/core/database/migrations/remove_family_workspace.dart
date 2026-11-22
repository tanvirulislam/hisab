import 'package:drift/drift.dart';

/// Schema v2 (D14): the Family workspace is removed for good.
///
/// Deletes the Family workspace and everything that belongs to it. A
/// transfer between Personal and Family is deleted as a whole (both legs),
/// since half a transfer would be an unexplained balance change. Children are
/// deleted before their parents, so this also works with foreign keys on.
Future<void> removeFamilyWorkspace(DatabaseConnectionUser db) async {
  const ws = "(SELECT id FROM workspaces WHERE type = 'family')";
  const acc = '(SELECT id FROM accounts WHERE workspace_id IN $ws)';
  const cats = '(SELECT id FROM categories WHERE workspace_id IN $ws)';
  const touches = '(workspace_id IN $ws OR account_id IN $acc OR counter_account_id IN $acc)';

  final statements = [
    'CREATE TEMP TABLE _doomed_txn (id TEXT PRIMARY KEY)',
    'INSERT INTO _doomed_txn SELECT id FROM transactions WHERE $touches '
        'OR transfer_group_id IN (SELECT transfer_group_id FROM transactions '
        'WHERE transfer_group_id IS NOT NULL AND $touches)',
    'INSERT OR IGNORE INTO _doomed_txn SELECT id FROM transactions '
        'WHERE refund_of_id IN (SELECT id FROM _doomed_txn)',
    'CREATE TEMP TABLE _doomed_rule (id TEXT PRIMARY KEY)',
    'INSERT INTO _doomed_rule SELECT id FROM recurring_rules WHERE $touches',
    'DELETE FROM recurring_executions WHERE rule_id IN (SELECT id FROM _doomed_rule) '
        'OR transaction_id IN (SELECT id FROM _doomed_txn)',
    'UPDATE transactions SET recurring_rule_id = NULL '
        'WHERE recurring_rule_id IN (SELECT id FROM _doomed_rule)',
    'DELETE FROM transactions WHERE refund_of_id IS NOT NULL AND id IN (SELECT id FROM _doomed_txn)',
    'DELETE FROM transactions WHERE id IN (SELECT id FROM _doomed_txn)',
    'DELETE FROM recurring_rules WHERE id IN (SELECT id FROM _doomed_rule)',
    'DELETE FROM budgets WHERE workspace_id IN $ws OR category_id IN $cats',
    'DELETE FROM categories WHERE parent_id IN $cats',
    'DELETE FROM categories WHERE workspace_id IN $ws',
    'DELETE FROM accounts WHERE workspace_id IN $ws',
    'DELETE FROM workspace_members WHERE workspace_id IN $ws',
    "DELETE FROM workspaces WHERE type = 'family'",
    'DROP TABLE _doomed_txn',
    'DROP TABLE _doomed_rule',
  ];
  await db.transaction(() async {
    for (final sql in statements) {
      await db.customStatement(sql);
    }
  });
}
