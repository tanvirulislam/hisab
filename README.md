# Hisab — হিসাব

Offline-first personal & family expense manager for Android, built with Flutter.

- Personal and Family workspaces, kept separate at the data level, plus a Combined overview
- Quick manual entry, voice entry (Bangla / English) and one-tap repeat
- Daily, weekly, monthly and category reports
- Budgets, recurring transactions, local backup & restore
- Bangladeshi Taka (৳). Amounts are stored as integer paisa, never floating point
- Bangla and English UI

**Status:** in development (Phase 1 — Foundation).

## Docs

- [Architecture & analysis](docs/ARCHITECTURE.md)

## Tech stack

Flutter · Riverpod · Drift (SQLite) · GoRouter · fl_chart · speech_to_text · flutter_local_notifications

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```
