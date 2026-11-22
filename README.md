# Hisab — হিসাব

Offline-first personal expense manager for Android, built with Flutter.

- Quick manual entry, voice entry (Bangla / English) and one-tap repeat
- Daily, weekly, monthly and category reports
- Budgets, recurring transactions, local backup & restore
- Bangladeshi Taka (৳). Amounts are stored as integer paisa, never floating point
- Bangla and English UI

**Status:** Phases 1–4 complete (foundation, transactions, dashboard and reports, budgets, voice, recurring, notifications). Next is Phase 5 (backup and restore, app lock, release).

## Docs

- [Architecture & analysis](docs/ARCHITECTURE.md)

## Tech stack

Flutter · Riverpod · Drift (SQLite) · GoRouter · fl_chart · speech_to_text · flutter_local_notifications

## Getting started

```bash
flutter pub get
dart run build_runner build
flutter run
```

## Tests

```bash
flutter test
```
