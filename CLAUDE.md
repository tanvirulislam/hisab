# Hisab: project brief for Claude

Read this first. Open other files only for the part you are changing. **Keep this file current**:
when a task changes status, a decision or a gotcha, update the relevant line in the same commit.

## What it is
- Offline Flutter **Android-only** expense manager for one person (BDT ৳, Bangla + English).
- App ID `com.hisab.app`. Repo `github.com/tanvirulislam/hisab`, branch `main`.
- Flutter 3.47.9 / Dart 3.13.7.
- Stack: Riverpod 3.5 (+ generator), Freezed 4, Drift 2.35 (`drift_flutter`, background isolate),
  go_router, intl/gen-l10n, flutter_local_notifications 23.

## Status (update this)
- **Done:**
  - Phase 1 (foundation), Phase 2 (transactions), Phase 3 (dashboard + reports).
  - Phase 4 (budgets, voice entry, recurring, notifications).
  - App icon, release ProGuard rules.
  - Family workspace removed permanently (D14, schema v2).
  - D15 "month starts on day N" (salary day, 1..28, `MonthCycle`), 2026-11-22. Not yet checked
    on a device. Phase 5 backup must carry the `month_start_day` setting.
- **Phase 5 (only when the owner asks):**
  - Backup/restore (SAF + share, validated restore, safety backup).
  - PIN/biometric lock, integration tests for the §25 workflows, performance pass.
  - Real release signing (currently debug-key signed), APK + AAB.
- **Ideas / PRD not yet built:** PRD §16 backup, §17 security, §29 future roadmap.

## Where to look (don't read whole files)
- `docs/memory/`: Claude's working notes (status, how the owner wants work done). They used to live outside the repo.
- `docs/ARCHITECTURE.md`: decisions **D1–D15** in §2.
  - Folder layout: §3.2. DB/ER: §4. Rule→enforcement map: §5. Navigation: §7. Tasks per phase: §8.
  - Phase notes: §11 (P2), §12 (P3), §13 (P4). Grep `### D` or `^## ` to jump.
- `hisab_prd.md` (untracked, 1500 lines, original spec): grep `^# ` for sections.
  - Key sections: §6 transactions, §11 reports, §12 budgets, §16 backup, §17 security.
  - Also: §22 DB, §23 financial rules, §25 tests, §27 MVP acceptance.
  - The PRD still mentions Family; **D14 overrides it**.
- Code: `lib/features/<feature>/{data,domain,presentation}`.
  - Features: accounts, budgets, categories, dashboard, more, notifications, recurring, reports,
    settings, transactions, voice, workspaces.
  - Shared code in `lib/core/`: `database/` (tables, daos, migrations, seed), `utils/` (money,
    local_date, month_cycle, bn_digits), `widgets/`, `services/`, `errors/`.
  - App shell: `lib/app/` (router, theme, app_maintenance).
- Tests mirror lib under `test/`. Helpers: `test/helpers/{test_db,app_harness,fakes}.dart`.

## Core rules (from decisions)
- Money is an integer number of **paisa** (D1). IDs are UUIDv7 text (D2).
- Date = `local_date` yyyymmdd + time (D3).
- Transfer = two linked rows (D4). Refunds and corrections are separate rows (D5).
- Balances and summaries are computed, never stored (D6). Deletes are soft (D7).
- Categories are global, and system names are translated via `system_key` (D8).
- Recurring rules can't create duplicates (D11). The voice parser sits behind an interface (D12).
- A "month" is cut only by `MonthCycle` (D15); never use `DateRange.month` for app periods.
- Single Personal workspace (D14). The `workspace_id` columns stay; queries use the one workspace's ID.
- Business rules belong in `domain/`. Notifiers only coordinate. Repositories return `Stream` for
  views and `Future` for commands, and throw typed `AppException`s that the UI maps to l10n text.

## Gotchas
- **Riverpod pauses unlistened stream providers**, so `read(x.future)` hangs forever.
  Call `container.listen(...)` first, in `main.dart` and in tests. This caused the device
  splash-screen hang.
- Generated code is gitignored. After pulling, or after changing Freezed/Drift/Riverpod/arb files,
  regenerate (commands below).
- Schema is **v2**. A schema change needs: bump `schemaVersion`, add a migration in
  `core/database/migrations/`, add a test in `test/core/database/database_test.dart`.
- Account `type` has a CHECK constraint (e.g. `bkash`, not `mobile_banking`).
- Every user-facing string goes in **both** `lib/l10n/app_bn.arb` and `app_en.arb`.

## Commands
```
dart run build_runner build -d && flutter gen-l10n   # codegen
flutter analyze && flutter test                       # must be clean / all pass (203 at f7d105a)
flutter run                                           # phone over adb; slow Gradle → run in background
flutter build apk --release                           # only when the owner asks
```
adb: `/home/spordium/Android/Sdk/platform-tools/adb`.
Last APK: `~/Documents/hisab-release/hisab.apk`.

**Put a release build on the owner's phone without losing data**:
- Run `flutter run --release -d R58R845GQ5N` (Samsung A22). It updates in place, so no APK copying.
- Debug and release are both signed with the debug key, so the app is never uninstalled.
- Back up first, while a *debug* build is installed (run-as only works on debuggable builds):
  `adb exec-out run-as com.hisab.app cat app_flutter/hisab.sqlite > ~/Documents/hisab-release/data-backup/<date>_hisab.sqlite`.
- When Phase 5 adds a real release key, the signature changes. Android will then refuse the update,
  and an uninstall would wipe the data. Back up and restore before switching keys.

## Working with the owner
- Reply in **Bangla**, with English technical terms. Make architecture decisions yourself and record
  them as a new D-number in ARCHITECTURE.md §2.
- When work is done: analyze + test, then **commit and push** to `main`.
- No release build unless asked. The owner has real data on their phone, so every schema change
  must migrate safely.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- graphify-out/ is gitignored (local only). Fresh clone: `graphify extract . --code-only && graphify cluster-only .`
  (AST only; `.graphifyignore` skips the platform folders). Docs/PRD are not in the graph, so grep those.
