# Personal Spending Tracker

Single-user, offline-first expense tracker. Flutter, local SQLite, no accounts, no server.

## Source of truth

`docs/spending-tracker-spec.md` is a **locked product spec** — treat it as read-only. If work seems to
require contradicting it, stop and raise it rather than reinterpreting. Its §6 non-goals are
guardrails: no multi-user, no sync, no multi-currency, no income/refunds, no edit audit trail, no
duplicate detection, no bank integration.

`docs/implementation-plan.md` holds the data model, phase briefs, and the fixed name inventory
(Appendix C) — consult it before inventing a repository method or provider name.

Section numbers below refer to the spec.

## Stack

drift + drift_flutter (SQLite) · Riverpod 2 (hand-written providers) · go_router · fl_chart ·
csv + share_plus + path_provider + file_selector · uuid · intl

## Locked decisions

- **Money is `int` cents.** Never `double`, never `String`, anywhere. Parse and format only at the UI
  edge via `core/money.dart`.
- **Timestamps are UTC epoch millis** in the DB; convert to local only for display.
- **Primary keys are UUID v7 strings**, generated in Dart. No autoincrement integers.
- **Soft delete everywhere** (`deleted_at`). Every read filters `deleted_at IS NULL`. This is a sync
  tombstone, not an audit trail.
- **Categories and Payment Methods share the `labels` table**, discriminated by `kind`. §2.4 gives
  them identical rules, so repositories, the picker, and the manage screen are written once and
  parameterized by kind. Never add a second table for one of them.
- **"No Category" / "No Payment Method" are real seeded rows** at fixed UUIDs. They cannot be
  renamed, deleted, moved, or used as a parent.
- **Needs-attention (§2.6) is derived, never stored** — an entry is flagged iff it points at a
  placeholder. Do not add a flag column.
- **Category rollup uses the recursive CTE** in `label_dao.dart`. Do not walk trees in Dart.
- **`TransactionFilter` is the only filtering vocabulary.** History, Analytics, and CSV export all
  take one. Export has no filter logic of its own — that's what makes §2.9 true by construction.
- **One Material 3 design across iOS and Android** (§2.10 decision). Adapt only where the platform
  genuinely differs: share sheet, date picker, back-swipe.
- **Default date range is Last 30 days.** Analytics buckets are user-selectable Day/Week/Month,
  defaulting to Week; a week is always 7 calendar days, and the *default* falls back to Day when the
  range spans under 14 days. The manual toggle always wins.
- **Labels can be reparented** (not in the spec; added deliberately). Validity:
  `newParentDepth + 1 + subtreeHeight <= 2`, no cycles, no duplicate sibling name. A move shifts
  `depth` across the whole subtree in one transaction, leaves transactions untouched, and shifts
  analytics rollups.

## Layering

`core` (pure Dart, no Flutter imports) ← `data` ← `features` / `shared`.
Features never import other features — promote anything shared to `shared/`.
drift's generated row classes are the domain model; add hand-written models only for composites.

## Confirmations

**Every create, rename, move, and delete confirms first**, via the shared `confirmDialog()` in
`shared/widgets/confirm_dialog.dart`. Each dialog states impact counts from a `preview*` repository
call — how many entries a rename touches, how many sub-labels a delete takes with it, how many
entries fall back to "No Category". Never wire a structural mutation straight to an `onPressed`.

## Staying iOS-clean

iOS cannot be built on this Windows machine and Mac access is limited, so avoid accumulating iOS debt:

- Before adding any package, confirm it lists **iOS** support on pub.dev.
- Never write to a hardcoded path — always `path_provider`.
- iOS has no user-visible filesystem: files reach the user via the **share sheet**, not a save path.
- No Android-only permission flows in shared code.

## Conventions

- Every multi-step write goes in a single `db.transaction { }` — cascade delete + reassign, and
  move + depth-shift, must be atomic.
- UI reads DB state through drift `.watch()` streams behind a `StreamProvider`. Do not manually
  invalidate providers after a write; the stream handles it.
- Filtered views show a true empty state — never silently fall back to unfiltered data (§5).
- Schema changes bump the drift schema version and add a migration test. The on-device DB is the
  user's only copy; there is no backup to restore from.
- Before writing chart code, load the `dataviz` skill.

## Commands

```
flutter run -d windows            # fastest inner loop
flutter run -d <android-device>
dart run build_runner build --delete-conflicting-outputs   # after touching tables/ or database.dart
flutter analyze
flutter test
```

## Design north star

§1: manual entry must be fast enough to become a habit. When a change adds a tap, a required field,
or a confirmation to the **add-transaction** path, that's a real cost — weigh it explicitly. (The
confirmation policy above applies to label and delete operations, not to logging a transaction.)
