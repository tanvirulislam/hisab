---
name: hisab-project-status
description: "Hisab Flutter app — repo location, phase progress, approved architecture decisions"
metadata:
  type: project
---

Hisab is a Flutter expense manager built phase by phase from the PRD (§26 roadmap). The public repo is https://github.com/tanvirulislam/hisab (branch main). docs/ARCHITECTURE.md is the approved design (D1–D15).

- Phase 1 (Foundation) was done and pushed on 2026-11-21.
- Phase 2 (Transactions) was done on 2026-11-21. Its decisions are in ARCHITECTURE.md §11.
- Phase 3 (dashboard and reports) was done on 2026-11-21. Its decisions are in ARCHITECTURE.md §12.
- Phase 4 (budgets, voice, recurring, notifications) was done on 2026-11-21. Its decisions are in ARCHITECTURE.md §13. compileSdk is 37.
- On 2026-11-22 the Family workspace was removed permanently (D14, schema v2).
- On 2026-11-22 a custom month start day was added (D15, salary cycle, no schema change).
- Phase 5 (backup/restore, app lock, release build) waits until the user asks for it.
- The live status, map and gotchas are in the repo's CLAUDE.md, which is auto-loaded. Update CLAUDE.md, not this memory, when status changes.

**Why:** The user approved the architecture and app ID `com.hisab.app` on 2026-11-21. They want a commit and push after each phase.

**How to apply:** Continue with the next phase in ARCHITECTURE.md §8. Generated code is gitignored, so run `dart run build_runner build` after a fresh clone. See [[hisab-decision-autonomy]].
