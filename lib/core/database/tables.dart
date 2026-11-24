// Drift table definitions for schema v1.
//
// Rules (see docs/ARCHITECTURE.md):
// - Primary keys are UUIDv7 text (D2).
// - Money is INTEGER paisa (D1).
// - Timestamps are INTEGER epoch milliseconds. `local_date` is yyyymmdd (D3).
// - Syncable tables have created_at / updated_at / deleted_at (D2, D7).
// - Rules that need other tables (workspace ownership etc.) are enforced
//   in repositories inside the write transaction.

import 'package:drift/drift.dart';

@DataClassName('WorkspaceRow')
class Workspaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get type => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  // 'family' is no longer used (D14); the constraint is left as created in
  // schema v1, since changing a CHECK needs a full table rebuild.
  List<String> get customConstraints => [
    "CHECK (type IN ('personal', 'family'))",
  ];
}

/// Who can access a workspace. MVP has one local owner per workspace.
/// MVP has a single workspace (D14).
@DataClassName('WorkspaceMemberRow')
@TableIndex(
  name: 'workspace_members_unique',
  columns: {#workspaceId, #memberRef},
  unique: true,
)
class WorkspaceMembers extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get memberRef => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get role => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (role IN ('owner', 'member'))",
  ];
}

@DataClassName('AccountRow')
@TableIndex(name: 'accounts_workspace', columns: {#workspaceId})
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get type => text()();

  /// May be negative (e.g. an account that starts overdrawn).
  IntColumn get openingBalancePaisa =>
      integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('cash', 'bank', 'bkash', 'nagad', 'savings', 'other'))",
  ];
}

@DataClassName('CategoryRow')
@TableIndex(name: 'categories_parent', columns: {#parentId})
@TableIndex(name: 'categories_workspace', columns: {#workspaceId})
class Categories extends Table {
  TextColumn get id => text()();

  /// NULL = shared by all workspaces.
  TextColumn get workspaceId =>
      text().nullable().references(Workspaces, #id)();

  /// NULL = top-level category; otherwise a subcategory of [parentId].
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  TextColumn get type => text()();

  /// Stable key for seeded categories (e.g. `grocery.fish`). The UI shows
  /// a translated name for these. User-created categories have NULL.
  TextColumn get systemKey => text().nullable().unique()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('expense', 'income'))",
    'CHECK (parent_id IS NULL OR parent_id <> id)',
  ];
}

/// Ledger rows. A transfer is two rows (transfer_out + transfer_in) that
/// share `transfer_group_id` (D4). A refund points at its expense through
/// `refund_of_id` (D5).
@DataClassName('TransactionRow')
@TableIndex(name: 'txn_workspace_date', columns: {#workspaceId, #localDate})
@TableIndex(name: 'txn_account', columns: {#accountId})
@TableIndex(
  name: 'txn_workspace_category_date',
  columns: {#workspaceId, #categoryId, #localDate},
)
@TableIndex(name: 'txn_transfer_group', columns: {#transferGroupId})
@TableIndex(name: 'txn_refund_of', columns: {#refundOfId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get type => text()();
  IntColumn get amountPaisa => integer()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get subcategoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get description => text().nullable().withLength(max: 500)();

  /// Calendar date chosen by the user, yyyymmdd. Reports use this column.
  IntColumn get localDate => integer()();

  /// Chosen date and time, epoch milliseconds. Used for ordering within a day.
  IntColumn get occurredAt => integer()();
  TextColumn get transferGroupId => text().nullable()();
  TextColumn get counterAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get refundOfId =>
      text().nullable().references(Transactions, #id)();
  TextColumn get recurringRuleId =>
      text().nullable().references(RecurringRules, #id)();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_paisa > 0)',
    "CHECK (type IN ('income', 'expense', 'refund', 'transfer_out', 'transfer_in'))",
    "CHECK (source IN ('manual', 'voice', 'recurring', 'repeat'))",
    'CHECK (local_date BETWEEN 19000101 AND 29991231)',
    // Income/expense/refund carry a category and no transfer fields;
    // transfer legs carry transfer fields and no category.
    "CHECK ((type IN ('income', 'expense', 'refund') AND category_id IS NOT NULL "
        'AND transfer_group_id IS NULL AND counter_account_id IS NULL) '
        "OR (type IN ('transfer_out', 'transfer_in') AND category_id IS NULL "
        'AND subcategory_id IS NULL AND transfer_group_id IS NOT NULL '
        'AND counter_account_id IS NOT NULL))',
    "CHECK ((type = 'refund') = (refund_of_id IS NOT NULL))",
    'CHECK (counter_account_id IS NULL OR counter_account_id <> account_id)',
  ];
}

@DataClassName('BudgetRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX budgets_unique_month ON budgets '
  '(workspace_id, category_id, year, month) WHERE deleted_at IS NULL',
)
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get amountPaisa => integer()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();

  /// Warning threshold as a percentage of [amountPaisa].
  IntColumn get warningThreshold =>
      integer().withDefault(const Constant(80))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_paisa > 0)',
    'CHECK (month BETWEEN 1 AND 12)',
    'CHECK (year BETWEEN 1900 AND 2999)',
    'CHECK (warning_threshold BETWEEN 1 AND 100)',
  ];
}

/// Template and schedule for a repeating transaction. A custom schedule is
/// [frequency] × [intervalCount] (e.g. every 2 weeks).
@DataClassName('RecurringRuleRow')
@TableIndex(name: 'recurring_workspace', columns: {#workspaceId})
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get type => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get counterAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get subcategoryId =>
      text().nullable().references(Categories, #id)();
  IntColumn get amountPaisa => integer()();
  TextColumn get description => text().nullable().withLength(max: 500)();
  TextColumn get frequency => text()();
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer().nullable()();
  IntColumn get nextDueDate => integer()();
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_paisa > 0)',
    "CHECK (type IN ('income', 'expense', 'transfer'))",
    "CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly'))",
    'CHECK (interval_count >= 1)',
    "CHECK ((type = 'transfer') = (counter_account_id IS NOT NULL))",
    "CHECK ((type = 'transfer') = (category_id IS NULL))",
  ];
}

/// One row per generated (or skipped) occurrence. The UNIQUE index makes
/// duplicate generation impossible, even after restarts (D11).
@DataClassName('RecurringExecutionRow')
@TableIndex(
  name: 'recurring_exec_unique',
  columns: {#ruleId, #occurrenceDate},
  unique: true,
)
class RecurringExecutions extends Table {
  TextColumn get id => text()();
  TextColumn get ruleId => text().references(RecurringRules, #id)();
  IntColumn get occurrenceDate => integer()();

  /// NULL when the occurrence was skipped.
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();
  IntColumn get executedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A person you lend money to or borrow from (D16).
@DataClassName('PersonRow')
@TableIndex(name: 'persons_workspace', columns: {#workspaceId})
class Persons extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get phone => text().nullable().withLength(max: 30)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One step of a loan with a person (D16). These rows are NOT income or
/// expense: they move account balances (when [accountId] is set) but never
/// reach income/expense reports or budgets.
///
/// `lent` / `borrowed` may have no account: an old loan that happened before
/// the app, so no account balance changes. A repayment always has an account.
@DataClassName('LoanEntryRow')
@TableIndex(name: 'loan_person', columns: {#personId})
@TableIndex(name: 'loan_account', columns: {#accountId})
class LoanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text().references(Workspaces, #id)();
  TextColumn get personId => text().references(Persons, #id)();
  TextColumn get accountId => text().nullable().references(Accounts, #id)();
  TextColumn get kind => text()();
  IntColumn get amountPaisa => integer()();
  IntColumn get localDate => integer()();
  TextColumn get note => text().nullable().withLength(max: 500)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_paisa > 0)',
    "CHECK (kind IN ('lent', 'repaid_to_me', 'borrowed', 'repaid_by_me'))",
    'CHECK (local_date BETWEEN 19000101 AND 29991231)',
    "CHECK (kind IN ('lent', 'borrowed') OR account_id IS NOT NULL)",
  ];
}

/// Key/value settings that are included in backups (D10).
@DataClassName('AppSettingRow')
class AppSettingsTable extends Table {
  @override
  String get tableName => 'app_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
