# HISAB
## Personal & Family Expense Manager
### Complete Product Requirements Document (PRD) & Technical Implementation Blueprint

**Document Version:** 1.0  
**Project Type:** Personal Finance Management Android Application  
**Platform:** Android  
**Primary Currency:** Bangladeshi Taka (BDT / ৳)  
**Primary Language:** Bangla + English (Switchable)  
**Framework:** Flutter  
**Status:** Ready for AI Agent Implementation

---

# 1. PROJECT OVERVIEW

## 1.1 Product Vision

Hisab is an offline-first personal and family expense management application designed to help users record daily income, expenses, transfers, and savings without the friction of traditional bookkeeping.

The primary problem this application solves is the difficulty of maintaining daily financial records consistently.

The user frequently makes small daily expenditures, including:

- Grocery and household shopping.
- Breakfast, lunch, dinner, and snacks.
- Office transportation.
- Drinking water and water jars.
- Medicine and healthcare.
- Personal purchases.
- Family-related expenses.
- Utility bills.
- Other miscellaneous expenses.

The user does not consistently record these expenses manually in a notebook. Consequently, it becomes difficult to understand monthly spending patterns and identify where money is going.

Hisab should make expense recording extremely simple, preferably taking only 5–10 seconds per transaction.

The application must automatically generate meaningful financial summaries and reports.

## 1.2 Core Objectives

1. Make daily expense recording effortless.
2. Support both Personal and Family financial workspaces.
3. Provide manual and voice-based transaction entry.
4. Automatically calculate daily, weekly, and monthly expenses.
5. Provide category-wise expense breakdowns.
6. Track income, expenses, account balances, and savings.
7. Support monthly budgets and spending alerts.
8. Work completely offline.
9. Provide reliable local backup and restore.
10. Maintain an architecture that supports future cloud synchronization and multi-device family access.

## 1.3 Target User

Initially, the application will be used by one person on one Android device.

The user wants to maintain two independent financial workspaces:

- Personal: Individual income and expenses.
- Family: Household and family income and expenses.

Future expansion should allow the user's spouse to access the shared Family workspace from another device.

---

# 2. PRODUCT SCOPE

## 2.1 Platform

- Android application only for the initial release.
- Flutter-based implementation.
- Responsive UI for different Android screen sizes.
- Offline-first architecture.

## 2.2 Language

Support two languages:

- Bangla (বাংলা)
- English

Provide a language switch in Settings.

All user-facing labels, categories, navigation labels, validation messages, and notifications must support localization.

## 2.3 Currency

Default currency: BDT (৳).

Display examples:

- ৳350
- ৳1,500
- ৳35,000

Use integer-based monetary storage in the smallest currency unit (paisa).

Example:

৳100.50 = 10050 paisa.

Never use floating-point arithmetic for financial calculations.

---

# 3. WORKSPACE MANAGEMENT

Workspace management is a fundamental part of the application.

## 3.1 Personal Workspace

Used for:

- Personal transportation.
- Personal food expenses.
- Personal shopping.
- Personal medicine.
- Individual income and salary.
- Other personal expenditures.

## 3.2 Family Workspace

Used for:

- Grocery and household shopping.
- Family food expenses.
- Household bills.
- Family medicine.
- Wife-related expenses.
- Family transportation.
- Shared household purchases.

## 3.3 Combined Financial Overview

Provide an optional Combined Overview that aggregates Personal and Family financial data.

Users must be able to see:

- Total personal expenses.
- Total family expenses.
- Combined expenses.
- Personal income.
- Family income.
- Combined income.
- Combined savings and remaining balances.

Important: Workspace separation must be maintained at the data level, not just visually.

Every workspace-specific transaction must be associated with a valid workspace ID.

## 3.4 Initial Family Usage

Initially, both workspaces will be managed on the same Android device.

Do not implement mandatory login or cloud authentication in MVP.

Design the database and repository architecture so future shared Family workspace access can be added without redesigning the application.

---

# 4. APPLICATION NAVIGATION

Use a five-item bottom navigation bar.

1. Home
2. History
3. Add
4. Reports
5. More

## 4.1 Home

Primary financial dashboard.

## 4.2 History

Daily and historical transaction list.

## 4.3 Add

Quick transaction entry.

## 4.4 Reports

Daily, weekly, monthly, and category-wise financial reports.

## 4.5 More

- Budgets.
- Categories.
- Accounts.
- Settings.
- Backup and Restore.
- About.

---

# 5. DASHBOARD REQUIREMENTS

The Home Dashboard must provide a clear financial overview.

## 5.1 Summary Cards

Display:

- Total Balance.
- Monthly Income.
- Monthly Expenses.
- Remaining Budget.
- Today's Expenses.

Allow switching between:

- Personal.
- Family.
- Combined.

## 5.2 Dashboard Components

Required components:

1. Workspace switcher.
2. Monthly financial summary.
3. Daily spending chart.
4. Quick action buttons.
5. Recent transactions.
6. Budget utilization summary.
7. Monthly expense overview.

## 5.3 Quick Actions

Provide prominent actions:

- Add Expense.
- Add Income.
- Voice Entry.
- Transfer Money.

Quick Expense must be accessible with minimal navigation.

## 5.4 Dashboard Accuracy

The dashboard must calculate values from actual persisted transactions.

Do not hardcode demonstration values in production screens.

All summaries must update immediately after a successful transaction operation.

---

# 6. TRANSACTION MANAGEMENT

Transactions are the core domain of the application.

## 6.1 Transaction Types

Use three transaction types:

- Income
- Expense
- Transfer

Additionally, support refunds and corrections through an explicitly defined transaction workflow.

## 6.2 Expense Entry

Required fields:

- Amount.
- Workspace.
- Category.
- Subcategory (optional).
- Account.
- Description (optional).
- Transaction date.
- Transaction time.
- Created timestamp.
- Updated timestamp.

Optional future fields:

- Attachment.
- Receipt image.
- Notes.

## 6.3 Income Entry

Support:

- Salary.
- Bonus.
- Freelance Income.
- Business Income.
- Other Income.

Income must be recorded independently of expenses.

## 6.4 Transfer Entry

Users should be able to transfer money between:

- Cash.
- Bank accounts.
- bKash.
- Nagad.
- Other accounts.

A transfer must not be counted as an expense or income in combined financial reports.

Each transfer should have:

- Source account.
- Destination account.
- Amount.
- Date.
- Description.

Transfers between Personal and Family workspaces must have explicitly defined accounting treatment to avoid double counting.

## 6.5 Transaction Operations

Support:

- Create.
- Read.
- Update.
- Delete.
- Search.
- Filter.
- Sort.
- Duplicate/repeat transaction.

Use confirmation dialogs for destructive operations.

## 6.6 Transaction Validation

- Amount must be greater than zero.
- Workspace must exist.
- Account must exist.
- Category must be valid for the selected transaction type.
- Invalid or incomplete transactions must not be persisted.

---

# 7. CATEGORY MANAGEMENT

Categories should be configurable and extensible.

Provide default categories.

## 7.1 Default Expense Categories

### Grocery & Bazar

Subcategories:

- Rice.
- Fish.
- Meat.
- Chicken.
- Vegetables.
- Fruits.
- Oil.
- Milk.
- Eggs.
- Spices.
- Other Grocery.

### Food & Dining

- Breakfast.
- Lunch.
- Dinner.
- Snacks.
- Restaurant.
- Tea/Coffee.
- Outside Food.

### Transportation

- Office Transport.
- Bus.
- Rickshaw.
- CNG.
- Uber/Pathao.
- Other Transport.

### Medicine & Healthcare

- Medicine.
- Doctor Consultation.
- Medical Tests.
- Hospital.
- Other Healthcare.

### Utilities

- Drinking Water.
- Water Jar.
- Electricity.
- Gas.
- Internet.
- Mobile Recharge.
- Other Utilities.

### Household

- Cleaning Supplies.
- Kitchen Supplies.
- Household Items.
- Repairs.
- Other Household.

### Shopping & Personal Care

- Clothing.
- Shoes.
- Personal Care.
- Accessories.
- Other Shopping.

### Family

- Wife-related Expenses.
- Family Purchases.
- Family Activities.
- Other Family Expenses.

### Other Categories

- Entertainment.
- Education.
- Rent & Bills.
- Mobile & Internet.
- Gifts.
- Others.

## 7.2 Category Requirements

Users must be able to:

- Add categories.
- Edit categories.
- Delete unused categories.
- Create subcategories.
- Select category icons.
- Select category colors.
- View category-wise spending.

Prevent deletion of categories that are referenced by existing transactions unless a safe reassignment strategy is implemented.

Provide a default category for uncategorized transactions.

---

# 8. QUICK ENTRY EXPERIENCE

This feature has the highest product priority.

The application should minimize the time required to record a transaction.

Provide three entry modes:

1. Manual Entry.
2. Voice Entry.
3. Recent / Repeat Entry.

## 8.1 Manual Entry

Required UX:

- Amount input should be immediately accessible.
- Workspace selection should be simple.
- Category selection should use visual icons.
- Description should be optional.
- Default date should be today.
- Default account should be the last-used account.
- Save should require minimal interaction.

## 8.2 Recent Entries

Provide recently used categories and transactions.

Allow the user to repeat a previous transaction with one tap.

Example:

Last transaction:
Office Bus — ৳40.

The user can select Repeat and modify the amount if necessary.

## 8.3 Quick Entry Performance

Target:

- Open entry screen quickly.
- Save a manual transaction in approximately 5–10 seconds.
- No unnecessary mandatory description fields.
- No network dependency.

---

# 9. VOICE EXPENSE ENTRY

Voice-based expense entry is a core requirement.

The user should be able to speak naturally in Bangla or English.

Example 1:

"আজকে অফিস যাওয়া আসায় ৮০ টাকা খরচ হয়েছে।"

Expected interpretation:

- Type: Expense.
- Category: Transportation.
- Subcategory: Office Transport.
- Amount: ৳80.
- Description: Office transport.
- Workspace: Currently selected workspace.

Example 2:

"আজকে বাজারে মাছ কিনেছি ৩৫০ টাকা আর সবজি কিনেছি ১৫০ টাকা।"

Expected result:

Create two proposed transactions:

1. Fish — Grocery — ৳350.
2. Vegetables — Grocery — ৳150.

Example 3:

"আজকে ওষুধ কিনেছি ৫০০ টাকা।"

Expected interpretation:

- Category: Medicine & Healthcare.
- Amount: ৳500.

## 9.1 Voice Processing Flow

1. User taps microphone.
2. Request microphone permission.
3. Capture speech.
4. Convert speech to text.
5. Parse amount, category, date, description, and transaction type.
6. Display proposed transaction details.
7. Allow editing.
8. User confirms.
9. Persist transaction.

Never automatically save an uncertain voice interpretation without user confirmation.

## 9.2 Voice Technology

Initial implementation:

- Evaluate Android-compatible Speech-to-Text using `speech_to_text`.
- Support Bangla and English locale selection where available.
- Provide graceful fallback to manual entry.
- Clearly handle permission denial and recognition failures.

Do not make paid AI API integration mandatory for MVP.

Design voice parsing behind an abstraction so a future AI-powered parser can be integrated.

---

# 10. TRANSACTION HISTORY

Provide a chronological transaction history.

## 10.1 Grouping

Group transactions by date.

Example:

Today — 21 November

- Grocery — ৳350.
- Office Transport — ৳80.
- Lunch — ৳150.

Yesterday — 20 November

- Medicine — ৳500.
- Household — ৳300.

## 10.2 Filters

Support:

- All.
- Personal.
- Family.
- Income.
- Expense.
- Transfer.
- Category.
- Subcategory.
- Account.
- Date range.

## 10.3 Search

Allow searching transaction descriptions and category names.

---

# 11. FINANCIAL REPORTS

Reporting is one of the primary reasons this application exists.

## 11.1 Daily Report

Display:

- Total daily income.
- Total daily expense.
- Daily net movement.
- Transaction list.
- Category breakdown.

## 11.2 Weekly Report

Display:

- Total weekly spending.
- Daily spending comparison.
- Highest spending day.
- Average daily expense.

## 11.3 Monthly Report

Display:

- Monthly income.
- Monthly expense.
- Monthly net savings.
- Category-wise spending.
- Daily average expense.
- Highest spending day.
- Previous month comparison.

## 11.4 Category-wise Report

Example:

November 2026:

- Grocery: ৳6,000.
- Food: ৳3,500.
- Transportation: ৳2,500.
- Medicine: ৳1,500.
- Household: ৳2,500.
- Others: ৳2,500.

Total: ৳18,500.

All numbers above are illustrative.

## 11.5 Personal and Family Reports

Allow report scope selection:

- Personal only.
- Family only.
- Combined.

## 11.6 Charts

Use `fl_chart`.

Recommended charts:

- Daily bar chart.
- Weekly spending chart.
- Monthly spending trend.
- Category pie/donut chart.
- Budget utilization chart.
- Income versus expense chart.

## 11.7 Report Export

Future-compatible requirements:

- CSV export.
- Excel export.
- PDF export.
- Date-range export.

MVP should prioritize reliable on-screen reports before export functionality.

---

# 12. BUDGET MANAGEMENT

Users should be able to set monthly budgets.

Budget scope:

- Personal.
- Family.

Example:

| Category | Monthly Budget |
|---|---:|
| Personal Grocery | ৳3,000 |
| Family Grocery | ৳6,000 |
| Transportation | ৳2,000 |
| Medicine | ৳1,500 |
| Household | ৳3,000 |
| Others | ৳3,000 |

## 12.1 Budget Alerts

- 80% budget utilization: Warning.
- 100% budget utilization: Limit reached.
- Above 100%: Overspending notification.

Allow users to customize alert thresholds.

## 12.2 Budget Reports

Show:

- Allocated amount.
- Spent amount.
- Remaining amount.
- Utilization percentage.

Budget calculations must respect workspace, category, and calendar month.

---

# 13. ACCOUNT MANAGEMENT

Support multiple financial accounts.

Default account types:

- Cash.
- Bank.
- bKash.
- Nagad.
- Other.

Each account should contain:

- Account name.
- Account type.
- Opening balance.
- Current balance.
- Workspace association.
- Active/inactive status.

Account balance must be derived from opening balance and correctly classified transactions.

Do not confuse total spending with account balance.

---

# 14. RECURRING TRANSACTIONS

Support recurring transactions.

Examples:

- Monthly rent.
- Monthly internet bill.
- Monthly salary.
- Regular household bills.

Recurrence options:

- Daily.
- Weekly.
- Monthly.
- Custom schedule.

Requirements:

- Avoid duplicate generation.
- Track the execution date of each recurring occurrence.
- Allow pause/resume.
- Allow editing recurring rules.
- Never generate duplicate transactions after app restarts.

---

# 15. NOTIFICATIONS

Use local notifications.

Potential notifications:

- Daily expense reminder.
- Budget warning.
- Monthly summary.
- Upcoming recurring expense.

Daily reminder should be configurable.

The reminder should encourage users to record missing expenses without becoming intrusive.

---

# 16. DATA BACKUP AND RESTORE

MVP requirement: Local backup and restore.

Support:

- Manual backup.
- Restore from backup.
- Export backup file.
- Validate backup before restoration.
- Protect against corrupt backup files.

Important:

Do not store the only copy of the backup inside an application-private directory that is removed when the app is uninstalled.

Allow the user to save backup files to a user-accessible location.

Future phase:

- Cloud backup.
- Multi-device synchronization.
- Family workspace sharing.

Architecture must support future cloud sync without requiring changes to the domain model.

---

# 17. SECURITY AND PRIVACY

Requirements:

- Optional application PIN.
- Biometric lock.
- Secure local data handling.
- No unnecessary collection of personal information.
- No mandatory account registration in MVP.
- Clear backup and restore behavior.

Do not upload financial information to external servers without explicit user consent.

---

# 18. UI/UX DESIGN SYSTEM

## 18.1 Design Direction

Modern, minimal, premium-looking personal finance application.

The design must be:

- Clean.
- Easy to understand.
- Fast to navigate.
- Mobile-first.
- Suitable for everyday use.

## 18.2 Color Palette

Primary: `#153D32`

Secondary: `#398B72`

Accent: `#F4B942`

Background: `#F5F6F2`

Use appropriate semantic colors for income, expense, warnings, and errors.

Provide light and dark themes.

## 18.3 UI Components

Create reusable components:

- Financial Summary Card.
- Workspace Selector.
- Transaction Tile.
- Category Icon Tile.
- Amount Input.
- Quick Action Button.
- Budget Progress Indicator.
- Date Selector.
- Chart Container.
- Confirmation Dialog.
- Empty State.
- Error State.
- Loading State.

## 18.4 UI Quality

Avoid unnecessary screens and long forms.

Prioritize quick entry over visual complexity.

Every important screen must include loading, empty, and error states.

Do not display hardcoded demo transactions in production.

---

# 19. TECHNICAL STACK

Use the following preferred stack.

| Responsibility | Technology |
|---|---|
| Framework | Flutter |
| Language | Dart |
| State Management | Riverpod |
| Database | SQLite + Drift |
| Routing | GoRouter |
| Charts | fl_chart |
| Voice Recognition | speech_to_text |
| Notifications | flutter_local_notifications |
| Preferences | shared_preferences |
| Secure Storage | flutter_secure_storage |
| Date Formatting | intl |
| Model Generation | Freezed |
| Code Generation | build_runner |

Use stable, mutually compatible package versions at implementation time.

Do not blindly copy outdated dependency versions.

---

# 20. SOFTWARE ARCHITECTURE

Use Feature-based Clean Architecture.

Separate:

1. Presentation.
2. Domain.
3. Data.

## Suggested Project Structure

lib/
  app/
    app.dart
    router.dart
    theme/

  core/
    database/
    constants/
    services/
    utils/
    widgets/
    errors/

  features/
    dashboard/
      data/
      domain/
      presentation/

    transactions/
      data/
      domain/
      presentation/

    categories/
      data/
      domain/
      presentation/

    accounts/
      data/
      domain/
      presentation/

    workspaces/
      data/
      domain/
      presentation/

    budgets/
      data/
      domain/
      presentation/

    reports/
      data/
      domain/
      presentation/

    voice_entry/
      data/
      domain/
      presentation/

    settings/
      data/
      domain/
      presentation/

  main.dart

Each feature should own its relevant providers, models, repositories, use cases, screens, and widgets.

Avoid placing all business logic in UI widgets or Riverpod Notifiers.

---

# 21. RIVERPOD STATE MANAGEMENT

Recommended providers:

- `activeWorkspaceProvider`
- `transactionListProvider`
- `transactionFilterProvider`
- `addTransactionProvider`
- `monthlySummaryProvider`
- `dailySummaryProvider`
- `categoryExpenseProvider`
- `budgetProvider`
- `accountBalanceProvider`
- `voiceEntryProvider`
- `reportFilterProvider`
- `appSettingsProvider`

Requirements:

- Use generated Riverpod providers where appropriate.
- Use repository abstractions.
- Avoid unnecessary provider invalidation.
- Prefer targeted state updates and database stream subscriptions.
- Keep expensive aggregation out of widget build methods.
- Ensure all workspace-dependent queries respond to workspace changes.
- Prevent duplicate database writes.

---

# 22. DATABASE DESIGN

Use Drift with SQLite.

Recommended tables:

1. workspaces
2. workspace_members
3. transactions
4. categories
5. accounts
6. budgets
7. recurring_rules
8. recurring_executions
9. app_settings

## 22.1 Workspace

Fields:

- id
- name
- type
- created_at
- updated_at

Workspace types:

- personal
- family

## 22.2 Transaction

Fields:

- id
- workspace_id
- category_id
- account_id
- type
- amount_in_paisa
- description
- transaction_date
- created_at
- updated_at
- is_deleted (if using soft deletion)

For transfers, include:

- source_account_id
- destination_account_id
- transfer_reference_id

Use appropriate nullable constraints depending on transaction type.

## 22.3 Category

Fields:

- id
- name
- parent_id
- type
- icon
- color
- workspace_id (nullable for globally shared categories)
- is_default
- is_active
- created_at

## 22.4 Account

Fields:

- id
- workspace_id
- name
- type
- opening_balance_in_paisa
- is_active
- created_at
- updated_at

## 22.5 Budget

Fields:

- id
- workspace_id
- category_id
- amount_in_paisa
- year
- month
- warning_threshold
- created_at
- updated_at

## 22.6 Database Rules

- Use foreign keys.
- Use appropriate indexes.
- Use database transactions for multi-step financial operations.
- Implement database migrations.
- Never silently delete financial records.
- Validate workspace ownership of linked accounts and categories.
- Use deterministic transaction handling where needed.
- Use integer monetary values.
- Store timestamps consistently and display dates in the user's local timezone.

---

# 23. FINANCIAL BUSINESS RULES

These rules are mandatory.

1. Income increases account balance.
2. Expense decreases account balance.
3. Transfer decreases the source account and increases the destination account.
4. Transfers are excluded from expense and income totals.
5. Personal and Family reports must remain separate.
6. Combined reports must aggregate both workspaces without double counting.
7. Refunds must not be counted as new income without an explicit accounting rule.
8. Editing a transaction must update affected reports and account balances.
9. Deleting a transaction must recalculate all affected summaries.
10. Budget calculations must use expense transactions only, unless a specific adjustment rule is implemented.
11. A transaction must not reference an account or category from an unrelated workspace.
12. Historical reports must use the transaction date, not creation date.
13. Monthly boundaries must use the selected local calendar month.
14. All financial calculations must be deterministic and precise.

---

# 24. PERFORMANCE REQUIREMENTS

- Fast application startup.
- Fast quick-entry screen.
- Responsive transaction history.
- Efficient SQL aggregation.
- No unnecessary full-table reads.
- Pagination or lazy loading for large transaction histories.
- Database indexing for frequently queried fields.
- Minimal unnecessary widget rebuilds.
- Offline operations must never wait for network connectivity.

---

# 25. TESTING REQUIREMENTS

## Unit Tests

Test:

- Transaction calculations.
- Account balance calculations.
- Transfer accounting.
- Budget calculations.
- Monthly summaries.
- Workspace separation.
- Category aggregation.
- Refund handling.
- Recurring transaction generation.

## Database Tests

Test:

- Insert.
- Update.
- Delete.
- Foreign key constraints.
- Migration.
- Backup.
- Restore.
- Transaction rollback.

## Widget Tests

Test:

- Dashboard.
- Workspace switcher.
- Expense form.
- Voice confirmation screen.
- Transaction history.
- Report filters.
- Budget screens.

## Integration Tests

Test complete workflows:

1. Create Personal expense.
2. Create Family expense.
3. Switch workspace.
4. View separate reports.
5. View Combined report.
6. Transfer money.
7. Edit transaction.
8. Delete transaction.
9. Verify updated dashboard.
10. Backup and restore financial data.

---

# 26. DEVELOPMENT ROADMAP

## Phase 1 — Foundation

- Initialize Flutter project.
- Configure theme and localization.
- Configure GoRouter.
- Configure Riverpod.
- Set up Drift.
- Implement migrations.
- Create workspace management.
- Seed default categories and accounts.

Deliverable: Working application foundation.

## Phase 2 — Transaction Management

- Expense entry.
- Income entry.
- Transfer entry.
- Category selection.
- Account selection.
- Edit and delete.
- Transaction history.
- Search and filters.

Deliverable: Fully functional offline transaction management.

## Phase 3 — Dashboard and Reports

- Financial dashboard.
- Workspace switcher.
- Daily summary.
- Monthly summary.
- Category-wise reports.
- Charts.
- Combined financial overview.

Deliverable: Accurate financial analytics.

## Phase 4 — Budgets and Voice

- Monthly budgets.
- Budget alerts.
- Voice recognition.
- Transaction parsing.
- Confirmation workflow.
- Recent transaction shortcuts.
- Recurring transactions.

Deliverable: Smart and convenient expense tracking.

## Phase 5 — Backup and Release

- Backup.
- Restore.
- Export.
- App lock.
- Testing.
- Performance optimization.
- Android release build.

Deliverable: Production-ready MVP.

---

# 27. MVP ACCEPTANCE CRITERIA

The application will be considered MVP-ready only when all the following requirements are satisfied.

### Workspace

- Personal workspace works independently.
- Family workspace works independently.
- Combined overview displays accurate totals.
- Workspace switching does not mix data.

### Transactions

- User can add income, expense, and transfer.
- User can edit and delete transactions.
- Transaction history is accurate.
- Category and account filters work.

### Dashboard

- Income is accurate.
- Expense is accurate.
- Remaining balances are accurate.
- Daily totals are accurate.
- Monthly totals are accurate.

### Voice

- User can initiate voice recognition.
- Recognized text is displayed.
- Proposed transactions can be edited.
- User must confirm before saving.

### Reports

- Daily reports work.
- Monthly reports work.
- Category reports work.
- Personal and Family reports are separate.
- Combined report is accurate.

### Budget

- Users can set monthly budgets.
- Budget utilization is accurate.
- Notifications respect configured thresholds.

### Reliability

- Core functionality works offline.
- Financial data persists after app restart.
- Backup and restore work.
- Database migrations work.
- Financial calculations use integer monetary values.

---

# 28. OUT OF SCOPE FOR MVP

Do not implement these unless explicitly requested:

- Mandatory user registration.
- Paid subscriptions.
- Banking API integrations.
- Automatic bank transaction detection.
- Automatic SMS transaction parsing.
- AI financial advisor.
- Investment portfolio tracking.
- Web dashboard.
- iOS application.
- Multi-device Family synchronization.
- Complex cloud infrastructure.

Keep the architecture extensible for future development.

---

# 29. FUTURE VERSION ROADMAP

Potential V2 features:

1. Family cloud synchronization.
2. Spouse access from another Android device.
3. Shared family account.
4. AI-powered financial insights.
5. Natural-language expense entry.
6. Receipt scanning using OCR.
7. Advanced financial analytics.
8. Monthly automated financial summaries.
9. Cloud backup.
10. Data export to Excel and PDF.

---

# 30. INSTRUCTIONS FOR THE AI CODING AGENT

You are responsible for implementing Hisab as a real, production-quality Flutter application.

Act as a Senior Flutter Engineer, Software Architect, and Product Implementation Agent.

## Execution Rules

1. Read and understand this entire document before writing code.
2. Inspect the existing project and development environment before making changes.
3. If a project already exists, preserve useful existing code and architecture.
4. If no project exists, initialize a clean Flutter project.
5. Follow the agreed product scope and business rules.
6. Do not invent additional mandatory features.
7. Do not use mock data as production data.
8. Do not build unnecessary backend infrastructure.
9. Prioritize offline-first functionality.
10. Use maintainable, testable code.
11. Implement database migrations from the beginning.
12. Write unit tests for financial business logic.
13. Test Personal and Family data isolation.
14. Do not skip error handling.
15. Do not silently change architectural decisions.
16. Keep the UI polished and consistent across screens.
17. Do not implement every feature in one enormous code-generation operation.

## Required Working Process

### Step A: Analysis

Produce:

- Requirement breakdown.
- Architecture proposal.
- Database ER diagram.
- Feature dependency map.
- Screen navigation map.
- Implementation task list.

### Step B: Foundation

Implement:

- Project structure.
- Dependencies.
- Theme.
- Localization.
- Navigation.
- Database.
- Initial migrations.

### Step C: Feature Development

Implement one feature at a time.

For each feature:

1. Define data model.
2. Define repository contract.
3. Implement data source.
4. Implement domain logic.
5. Implement Riverpod providers.
6. Implement UI.
7. Add tests.
8. Verify functionality.

### Step D: Integration

Integrate all modules and verify:

- Workspace isolation.
- Transaction correctness.
- Dashboard calculations.
- Reports.
- Budgets.
- Voice entry.
- Backup and restore.

### Step E: Final Delivery

Provide:

- Working Flutter source code.
- Dependency list.
- Database schema.
- Architecture documentation.
- Test results.
- Setup instructions.
- Android APK.
- Production AAB build instructions.
- Known limitations.

## Important Final Instruction

Do not stop after generating a design or writing a technical plan.

The ultimate goal is a fully functional Android application that the user can use every day to manage real Personal and Family finances.

Build the application incrementally, validate each phase, and maintain financial data correctness as the highest priority.

---

# END OF PRODUCT SPECIFICATION

**Project:** Hisab  
**Version:** 1.0  
**Platform:** Android  
**Architecture:** Flutter + Riverpod + Drift/SQLite  
**Primary Goal:** Effortless daily expense tracking and accurate monthly financial visibility.
