# Task brief: Google Drive backup and restore (Phase 5, D22)

Written for a Claude Code session that will build this end to end without asking. Read
`CLAUDE.md` first; everything there still applies except where this brief says otherwise.

## 0. Ground rules for this task

- **Branch:** work on `feat/drive-backup` (already created from `main`, this file is its first
  commit). Commit there in small steps and push the branch. **Do not merge into `main`** and do
  not push to `main`; the owner merges after testing on the phone. This overrides CLAUDE.md's
  "commit and push to main".
- Reply to the owner in Bangla with English technical terms. Make architecture decisions
  yourself and record them (CLAUDE.md "Working with the owner").
- The owner has real data on the phone (Samsung A22, adb id `R58R845GQ5N`). **Never uninstall
  the app**, never clear its data. Installing a debug or release build over the current one is
  safe (both are signed with the same debug key, so it updates in place).
- No schema change is needed. If you find you need one, follow the CLAUDE.md schema gotcha
  (bump version, migration, migration test).
- Done = `flutter analyze` clean, `flutter test` all pass, `graphify update .`, CLAUDE.md and
  ARCHITECTURE.md updated, branch pushed, and a short Bangla report to the owner with the
  phone test checklist (§7).

## 1. What the owner decided (do not re-ask)

- Backups go **only to the owner's Google Drive**. No local save-to-file and no share option
  (the owner's reason: a lost phone or factory reset must not lose data).
- **No password/encryption** on the backup file.
- Google Drive, **not Firebase**.
- Daily automatic backup plus a "Back up now" button. Keep the newest **10** backups on Drive.
- On a fresh install with no user data, offer to restore from Drive.

## 2. Prerequisite done by the owner (you cannot do it)

A Google Cloud project with the Drive API enabled, an OAuth consent screen (External,
**published "In production"**, scope `https://www.googleapis.com/auth/drive.file` only), an
**Android** OAuth client (package `com.hisab.app`, SHA-1
`01:7F:82:29:F9:8F:8B:91:3C:15:21:0C:10:B1:95:B8:D0:6D:22:27`, the debug key that signs both
debug and release builds) and a **Web application** OAuth client. The owner gives you the Web
client ID in the prompt. It is not a secret: put it in
`lib/features/backup/data/drive_config.dart` as `const kGoogleServerClientId`. If the prompt
has no client ID, build and test everything with fakes, leave a clear TODO in that one file,
and tell the owner.

No `google-services.json` is needed (that is Firebase).

## 3. Decision D22 (write it into ARCHITECTURE.md §2, after D21)

D22 replaces the "where it is saved" part of D13 (SAF/share) with Google Drive. D13's file
format and validated, all-or-nothing restore stay. Write up these points:

- **Auth:** `google_sign_in` 7.x (`GoogleSignIn.instance.initialize(serverClientId: …)`,
  `authenticate()`, `attemptLightweightAuthentication()`, then
  `authorizationClient.authorizeScopes([DriveApi.driveFileScope])`), turned into an
  authenticated HTTP client with `extension_google_sign_in_as_googleapis_auth`, used by
  `googleapis` `DriveApi`. The 7.x API differs a lot from 6.x: read the package README and
  example on pub.dev before writing code. Check the versions work together before you add them
  (latest as of 2026-11-27: google_sign_in 7.2.0, googleapis 19.0.0,
  extension_google_sign_in_as_googleapis_auth 3.0.0, crypto 3.0.8).
- **Scope `drive.file` only.** The app sees only the files it made. It creates a folder
  **"Hisab Backup"** in My Drive (find it by name + `mimeType = folder` + `trashed = false`,
  create it if missing, remember its ID in LocalPrefs, re-find it if it was deleted).
- **File:** `hisab-backup-YYYYMMDD-HHmmss.hisab`, `mimeType: application/gzip`. Put the header
  summary in Drive `appProperties` (`hisab_format`, `schema`, `created_at`, `tx_count`) so the
  restore list shows date and counts without downloading.
- **Format (from D13):** gzip of UTF-8 JSON
  `{ "header": { "format_version": 1, "schema_version": 4, "app_version", "created_at",
  "counts": {table: n}, "sha256" }, "tables": { "<table>": [ {column: value}, … ] } }`.
  `sha256` is computed over the canonical JSON of `tables`. Dump tables generically with
  `customSelect('SELECT * FROM <t>')`. Get the table list from `sqlite_master` (skip
  `sqlite_%` and drift internals) and check it against `tables.dart`. Include every app table,
  the legacy `recurring_*` ones and `app_settings` too: it holds `month_start_day`, language,
  theme, reminders and the rest of the settings.
  Include soft-deleted rows: a backup is an exact copy.
- **Restore validation (all in memory, before touching the DB):** gzip decodes, JSON parses,
  `format_version` known, checksum matches, `schema_version == 4` (newer → "update the app"
  error; older → not possible yet, write the upgrade hook point), counts match, required
  columns present, every foreign key resolves, transfers come in linked pairs (D4), loan
  repayments never exceed what is open (D16), exactly one workspace (D14).
- **Restore write:** take a **safety backup** of the current data first (same format, app
  documents dir `safety/`, keep newest 3; this is only for "undo restore", not a backup).
  Then in **one Drift transaction** delete every table's rows in reverse-FK order and insert in
  FK order. Then run `PRAGMA foreign_key_check` and the domain checks again. Any failure throws,
  and the transaction rolls back, so nothing is half-restored. Afterwards: reschedule
  notifications from the restored settings (see `notification_coordinator.dart`), clear
  `LocalPrefKeys.budgetAlertLevels`, and make sure `lastAccountId` falls back if the account no
  longer exists. Streams refresh by themselves.
- **Auto backup:** no WorkManager. On app start and on resume (hook into `app/app_maintenance.dart`
  or the lifecycle), run in the background if all of these are true:
  - the user is signed in silently (`attemptLightweightAuthentication`, never a UI prompt);
  - the last successful backup was ≥ 24 h ago;
  - the data changed since that backup. Use a cheap fingerprint, e.g. row counts plus
    `MAX(updated_at)` per table, stored in LocalPrefs.

  No internet or any other failure means stay silent, record it, and show it on the Backup
  screen ("Last backup failed: no internet"). After a successful upload, delete the app's older
  backups beyond the newest 10. Never run two uploads at once.
  Put the "is a backup due" rule in `domain/` as a pure function of (now, last success,
  fingerprints) so it is unit-tested.
- **Per-device state in LocalPrefs** (not in the backup): last backup time and fingerprint,
  last error, Drive folder ID, the "restore offered" dismissal.
- **Errors:** add `BackupException` to the sealed `AppException` family
  (`core/errors/app_exception.dart`) with codes such as `notSignedIn`, `network`,
  `corruptFile`, `checksumMismatch`, `tooNew`, `invalidData`, `driveQuota`. Map every code to
  l10n text in **both** `app_bn.arb` and `app_en.arb`.
- **Permissions:** add `<uses-permission android:name="android.permission.INTERNET"/>` to
  `android/app/src/main/AndroidManifest.xml`. Release builds lack it today; Flutter only adds
  it to debug. The rest of the app stays fully offline. Check the release build with R8
  (`android/app/proguard-rules.pro`): add keep rules only if sign-in or Drive breaks in release.

## 4. Code layout

`lib/features/backup/`
- `domain/`: `backup_file.dart` (header model, encode/decode, checksum), `backup_validator.dart`,
  `backup_schedule.dart` (the pure "due?" rule), `backup_summary.dart` (counts for preview).
- `data/`:
  - `backup_repository.dart`: export the DB to a backup and restore a backup into the DB,
    inside a transaction.
  - `backup_store.dart`: `abstract interface class BackupStore { list, upload, download,
    deleteOld }`, implemented by `DriveBackupStore`.
  - `google_account.dart`: `abstract interface class GoogleAccount { email, signInSilently,
    signIn, signOut, authClient }`.
  - `drive_config.dart`: the client ID.

  Both interfaces exist so tests use fakes (`test/helpers/fakes.dart`).
- `presentation/`: providers (Riverpod generator), `backup_screen.dart`, restore list,
  preview/confirm dialog, the fresh-install restore offer, and `auto_backup` coordinator
  wiring.

Navigation: `MoreScreen` already has a Backup item with `route: null` ("coming soon"). Give it
`Routes.backup = '/more/backup'` inside the More branch, like the other More screens. The
screen has no Add action, so the tab bar Add keeps opening a transaction (D21).

## 5. Screens (Bangla first, English via l10n)

**Backup screen** (More → ব্যাকআপ ও রিস্টোর):
- Not signed in: a short explanation and a "Google দিয়ে login" button.
- Signed in:
  - account email and the "Hisab Backup" folder name;
  - last successful backup (relative time) or the last error;
  - "এখনই backup নিন" (shows progress, then a toast);
  - "Drive থেকে restore";
  - "আগের অবস্থায় ফিরুন" (only when a safety backup exists);
  - sign out.

**Restore list:** Drive backups newest first, with date/time and transaction count.
Tapping one does download → validate → preview (counts per kind: transactions, accounts,
categories, budgets, people, loan entries; backup date) → confirm dialog ("এখনকার সব ডেটা এই
backup দিয়ে বদলে যাবে। আগের অবস্থা আলাদা করে রাখা হবে।") → restore → toast.

**Fresh-install offer:** when the DB holds no user data (no transactions, persons or budgets;
the seeded categories and accounts do not count), show a dismissible card on Home or a
one-time dialog: "আগের ডেটা Drive-এ আছে? ফিরিয়ে আনুন". Show it once per install.

Follow the existing gotchas: no SnackBar (`showSnack` / `AppToast`), durations via `Motion`,
360dp phones must not overflow in either language (`test/small_screen_test.dart` pattern).

## 6. Tests (add to the suite; the count in CLAUDE.md must be updated)

- Codec: round-trip (export → restore into an empty test DB → every table identical);
  flipped byte → `checksumMismatch`; truncated gzip / not gzip → `corruptFile`;
  `schema_version` 5 → `tooNew`; dangling foreign key, broken transfer pair or over-repayment
  → `invalidData`.
- Restore: a failure in the middle (inject one) leaves the old data intact; a safety backup is
  written before the replace, and only 3 are kept; restore reschedules notifications
  (`RecordingNotifications`).
- Schedule rule: due / not due across 24 h, unchanged data, and a past failure.
- Store: retention keeps the newest 10 and deletes only the app's files (fake store).
- Widgets: signed-out → sign-in → back up now → list → preview → confirm → restored; the
  fresh-install offer shows once; error texts in bn and en; no overflow at 360dp.
- **Owner's real data, local only:** a test that, if
  `~/Documents/hisab-release/data-backup/2026-11-27_hisab.sqlite` exists, opens a *copy* of
  it, exports, restores into a fresh DB, and checks every row and every account balance is
  identical. Skip it when the file is missing (CI, other machines). **Never commit that file or
  any data from it.**

## 7. After the code: what to hand back to the owner

A Bangla message with:
1. What was built, and the branch name and last commit.
2. How to try it: `flutter run --release -d R58R845GQ5N`. This updates the app in place.
   Install over the existing app only; never uninstall.
3. Phone checklist:
   - Login works.
   - "Back up now" puts a file in Drive → "Hisab Backup" (check in the Drive app).
   - Add a transaction, reopen the app the next day or move the clock: the auto backup runs.
   - Restore that backup: the data comes back the same.
   - "Undo restore" works.
   - With airplane mode on, the error shows and nothing crashes.
4. A reminder: when Phase 5 adds the real release key, its SHA-1 must be added to the Android
   OAuth client, or sign-in fails. Add this to CLAUDE.md Gotchas too.
5. "Tell me to merge into main when it looks right."

## 8. Docs to update in the same branch

- `ARCHITECTURE.md`: D22 in §2; §7 navigation (Backup screen); §8 Phase 5 line; dependency
  table (replace file_picker/share_plus with google_sign_in, googleapis, extension, crypto).
- `CLAUDE.md`: Status (Phase 5 backup done on `feat/drive-backup`, not yet on device); decisions
  D1–D22; test count; Gotchas (INTERNET permission, SHA-1 on key change, `drive.file` only sees
  app-made files).
- `docs/memory/hisab-project-status.md` if it lists Phase 5 status.
