# Personal Spending Tracker

Single-user, offline-first expense tracker. Flutter, local SQLite, no accounts, no server.

## Source of truth

`docs/spending-tracker-spec.md` is a **locked product spec** — treat it as read-only. If work seems to
require contradicting it, stop and raise it rather than reinterpreting. Its §6 non-goals are
guardrails: no multi-user, no sync, no multi-currency, no income/refunds, no edit audit trail, no
duplicate detection, no bank integration.

`docs/implementation-plan.md` holds the data model, phase briefs, and the fixed name inventory
(Appendix C) — consult it before inventing a repository method or provider name.

`docs/user-guide.md` is the user-facing guide. It describes only what actually ships, and carries a
"Not built yet" section listing the rest. **At the end of each phase, move that phase's features out
of "Not built yet" and document the real behaviour** — including anything the app refuses to do, since
the limits (3-level cap, cascade delete, placeholder immutability) are the least discoverable part.
Update the status line and the README's phase status at the same time.

Section numbers below refer to the spec.

## Stack

drift + drift_flutter (SQLite) · Riverpod 2 (hand-written providers) · go_router · fl_chart ·
csv + share_plus + path_provider + file_selector · uuid · intl

Deps: see pubspec.yaml (Appendix A). Toolchain is Flutter 3.44.9 / Dart 3.12.2, so
`drift_flutter` is on `^0.3.1` as the plan intended — the old `^0.2.8` pin is resolved and gone.
Note that `sqlite3` 3.x now bundles the native library itself, which is why
`sqlite3_flutter_libs` / `sqlcipher_flutter_libs` resolve to empty `+eol` shim packages. That is
expected; don't try to "fix" it by pinning them back.

`drift_dev` is pinned to `^2.34.5` deliberately: 2.34.0 does **not** compile against `drift` 2.34.3
(its schema tooling references APIs that moved behind `drift3_preview`), which breaks every
`drift_dev schema` command. If those commands start failing to build, check this pairing first.

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
  **History and Analytics hold separate instances** (`historyFilterProvider` /
  `analyticsFilterProvider`) so the two views scope independently. "Export respects the active
  filter" therefore means *the invoking view's* filter — there is no global one to read.
- **A bulk write only ever touches visible rows.** Selection state is reconciled against the
  filtered list via `historyVisibleSelectionProvider`; act on that, never on the raw
  `historySelectionProvider`. Narrowing a filter after selecting must not leave entries staged for
  a write the user can no longer see.
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
- **Never step local calendar dates with `Duration`.** `add`/`subtract(Duration(days: n))` are
  absolute-time operations; across a DST boundary they land at 23:00 or 01:00 on a neighbouring
  date rather than local midnight. Use `DateTime(y, m, d + n)`, which normalizes overflow and
  always lands on midnight. This is not hypothetical — `bucketEnd` did exactly this and hung the
  app in an infinite loop for any Analytics range spanning a fall-back date (fixed in Phase 8; see
  `group('DST safety')` in `test/core/bucketing_test.dart`).
- Schema changes bump the drift schema version and add a migration test. The on-device DB is the
  user's only copy; there is no backup to restore from. The harness is live — see
  **Schema migrations** below for the exact steps.
- Before writing chart code, load the `dataviz` skill. Chart colors come from
  `features/analytics/widgets/chart_palette.dart` (the skill's validated slot-1 blue plus chrome
  inks, light and dark), **not** from the Material `ColorScheme` — scheme steps are tuned for UI
  affordances, not the chart contrast floor. Both charts are deliberately single-hue: the category
  breakdown is *nominal*, so bar length carries the magnitude and color is not spent re-encoding
  it. Don't "improve" it into one hue per category — that breaks past 8 categories and fails the
  skill's CVD checks.
- After changing a chart, **render it and look at it** — the palette validator checks color, not
  layout. Overlapping axis ticks and clipped labels only show up in a picture. A throwaway
  `matchesGoldenFile` test with `--update-goldens` dumps a PNG; text renders as boxes without
  fonts, which is fine for checking geometry. This is how the y-axis tick collision was caught.

## Commands

```
flutter run -d windows            # fastest inner loop
flutter run -d <android-device>
dart run build_runner build        # after touching tables/ or database.dart
flutter analyze
flutter test
flutter test --exclude-tags perf   # skip the ~5k-row benchmark for a fast loop
```

(`--delete-conflicting-outputs` is gone in the current build_runner — it now warns and ignores it.)

`test/data/perf_test.dart` (tag `perf`, seeded by `seed_dataset.dart`) is a real regression guard,
not a microbenchmark — it is what caught the DST bucketing hang. Keep it in the default run; its
timing budgets are deliberately loose.

## Schema migrations

Snapshots live in `drift_schemas/`, generated helpers in `test/data/generated_migrations/`
(both checked in, both regenerated by command — never hand-edit). `test/data/migration_test.dart`
asserts the live schema still matches the newest snapshot, so **editing `tables.dart` without
re-dumping fails the suite** rather than silently drifting.

When you change the schema:

1. Bump `schemaVersion` in `database.dart` and add an `onUpgrade` step for the new version.
2. `dart run build_runner build`
3. `dart run drift_dev schema dump lib/data/database.dart drift_schemas/`
4. `dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/`
5. Add a test that seeds a database **at the old version**, runs `migrateAndValidate`, and asserts
   the user's rows survived — not just that the shape is right. Shape-only tests pass while data
   is being destroyed, and there is no backup to restore from.

Verified end-to-end on an artificial v1→v2 column add: the harness passes a correct migration and
fails a migration that forgets the column, reporting the missing column by name.

## Design north star

§1: manual entry must be fast enough to become a habit. When a change adds a tap, a required field,
or a confirmation to the **add-transaction** path, that's a real cost — weigh it explicitly. (The
confirmation policy above applies to label and delete operations, not to logging a transaction.)
