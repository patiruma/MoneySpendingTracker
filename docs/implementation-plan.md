# Technical Plan — Personal Spending Tracker (Flutter)

> Section 4 is written so each phase can be executed in a **fresh session** with only:
> `spending-tracker-spec.md` + `CLAUDE.md` (auto-loaded from repo root) + this file.

## Context

[spending-tracker-spec.md](spending-tracker-spec.md) is a locked product spec for a single-user,
local-only expense tracker. Its core risk is stated in §1: **manual entry must be fast enough to
become an automatic habit**. §8 already locked the framework to Flutter.

The working directory currently contains only the spec — this is a greenfield build.

**Environment verified:** Flutter 3.44.9 / Dart 3.12.2, Android SDK 36.1.0, Windows desktop
(VS 2022), Chrome. No macOS toolchain on this machine.
(Originally scaffolded on Flutter 3.35.4 / Dart 3.9.2; upgraded during Phase 2 so `drift_flutter`
could move to the intended `^0.3.1`, which requires Dart ≥ 3.10.)

**Decisions confirmed in planning** (resolving spec §7 and the §2.10 deferral):

| Question | Decision |
| --- | --- |
| Default date range (§7) | **Last 30 days** (rolling) |
| Analytics line-graph buckets (§7) | **User-selectable Day/Week/Month, default Week.** A week is always 7 calendar days; when the selected range spans < 14 days the *default* falls back to Day so the chart isn't a single point. The manual toggle always overrides. |
| Per-platform UI (§2.10) | **One Material 3 design** for iOS + Android |
| iOS build path (§2.10) | **Defer iOS, stay iOS-clean**; Mac verification checkpoints at Phase 4 and Phase 8 |
| Reparenting labels | **In scope.** Not in the spec, but it's what makes nesting usable given that fast-path entry creates top-level labels only. Cheap to add (§2 below). |
| Confirmation coverage | **Every** create / rename / move / delete confirms first, with impact counts. Broader than the spec's §2.3/§2.4 minimum. |

---

## 1. Stack

| Concern | Choice | Why |
| --- | --- | --- |
| Local DB | **drift** + `drift_flutter` 0.3.x | Real SQL (recursive CTEs for rollup), reactive `.watch()`, first-class migrations, all five platforms from one call. Verified on pub.dev. |
| State | **Riverpod 2**, hand-written providers | Composable filter state; `StreamProvider` maps 1:1 onto drift's `watch()`. No `riverpod_generator` — build_runner already carries drift; one codegen tool keeps regeneration simple. |
| Charts | **fl_chart** 1.2.x | Line + bar, maintained, verified on pub.dev. |
| Routing | **go_router** | Named routes keep ~8 screens decoupled. |
| Export | `csv` + `share_plus` + `path_provider` (mobile), `file_selector` (desktop) | iOS has no user-visible filesystem; the share sheet is the correct handoff. |
| Misc | `uuid` (v7), `intl` | |

Full dependency list in **Appendix A**. Versions resolve at scaffold time — no pins beyond majors.

---

## 2. Data Model

Two tables. Amounts are **integer cents**, timestamps **UTC epoch millis**, PKs **UUID v7 strings**.
Literal drift definitions in **Appendix B**.

### `labels` — Categories *and* Payment Methods in one table

§2.4 gives Categories and Payment Methods **byte-identical rules**: freeform, 3-level nesting,
selectable at any level, create-with-confirmation, rename cascades, delete cascades to children,
in-use deletion reassigns to a placeholder. Two tables would duplicate the repository, tree builder,
type-ahead picker, cascade logic, move logic, and manage screen.

One table with a `kind` discriminator writes each of those **once**, parameterized by kind. The cost
is a `WHERE kind = ?` on every query. That trade is strongly worth it here.

Key columns: `id`, `kind`, `name`, `parent_id`, `depth` (0–2), `is_placeholder`, `sort_order`,
`created_at`, `updated_at`, `deleted_at`.

- `depth` is denormalized so the 3-level cap (§2.4) is a `CHECK`, not a recursive query per insert.
  It must be recomputed for the whole subtree on a move.
- Unique index on `(kind, IFNULL(parent_id,''), name) WHERE deleted_at IS NULL` — prevents duplicate
  siblings and drives the type-ahead's "does this already exist?" check.
- Two placeholder rows (`is_placeholder = 1`) seeded in migration v1 at **fixed, well-known UUIDs**
  (`kNoCategoryId` / `kNoPaymentMethodId`), guarded against rename, delete, move, and being a parent.

### `transactions`

Key columns: `id`, `amount_cents` (`CHECK > 0`), `occurred_at`, `category_id`, `payment_method_id`,
`note` (`CHECK` non-blank), `extra_notes`, `created_at`, `updated_at`, `deleted_at`.

### What falls out of this design

**Rename cascade (§2.4) is free.** Transactions reference labels by `id`, never by name, so a rename
is a one-row `UPDATE` and every past entry displays the new name. Nothing is orphaned.

**Reparenting is invisible to transactions**, for the same reason — but it *does* change analytics
rollups, since a moved subtree's spending now rolls up under a different parent. That consequence
belongs in the move confirmation dialog.

**"Needs attention" (§2.6) is derived, never stored.** Flagged iff
`category_id == kNoCategoryId || payment_method_id == kNoPaymentMethodId`. No boolean column to keep
in sync, and the flag clears itself the instant an entry is recategorized. Because placeholders are
ordinary rows with ordinary ids, they also work as normal filter values with zero special-casing —
exactly what §2.6 asks for.

**Category rollup (§2.8) is one recursive CTE**, not a Dart tree walk:

```sql
WITH RECURSIVE subtree(id) AS (
  SELECT id FROM labels WHERE id = :rootId AND deleted_at IS NULL
  UNION ALL
  SELECT l.id FROM labels l JOIN subtree s ON l.parent_id = s.id WHERE l.deleted_at IS NULL
)
```

The same CTE powers rollup totals, chart series, the filtered list, cascade delete, and move validation.

**Move validity math.** Let `h(x)` = subtree height of `x` (max descendant depth − depth of `x`; 0 for
a leaf). Moving `x` under parent `p` of depth `dp` (use `dp = -1` for top level) is valid iff:

```
dp + 1 + h(x) <= 2        // still within 3 levels
AND p != x AND p not in subtree(x)   // no cycles
AND no live sibling under p shares x's name
```

On success, shift `depth` by `(dp + 1) - depth(x)` across the whole subtree in one transaction.

**Text search (§2.7) uses `LIKE` over lowercased `note || extra_notes`.** A personal dataset is
thousands of rows; FTS5 would add sync triggers for no measurable gain. Escape hatch if it ever gets slow.

### Sync-readiness (§2.10)

§2.10 asks to keep the barrier to future sync low where it doesn't conflict with anything else.
Three habits buy most of that for near-zero cost:

1. **UUID v7 PKs** — no collisions when merging devices; time-sortable as a bonus.
2. **`created_at` / `updated_at` on every row** — the basis of any last-write-wins merge.
3. **Soft delete (`deleted_at`)** — hard deletes are unmergeable; a tombstone is one column plus one
   predicate. This is *not* an audit trail (no field-level history), so it doesn't conflict with §6.

Explicitly **not** building now: no CRDTs, no vector clocks, no sync engine, no server.

### `TransactionFilter` — one object, three consumers

```dart
class TransactionFilter {
  final DateRange range;          // preset (default: last30Days) or custom
  final String? categoryId;       // null = all; placeholder id is a normal value
  final bool rollupCategory;      // include descendants
  final String? paymentMethodId;
  final String query;             // matches note + extra_notes
}
```

Satisfies three requirements at once: composable filters (§2.7), "reuse the history list rather than
duplicate it" (§2.8.4), and "export respects whatever filters are active" (§2.9). Export takes a
`TransactionFilter` and has no filter logic of its own — that's what makes §2.9 true by construction.

---

## 3. Folder Structure

```
money_spending_tracker/
├─ CLAUDE.md
├─ docs/
│  ├─ spending-tracker-spec.md       # locked source of truth, do not edit
│  └─ implementation-plan.md         # this file
├─ analysis_options.yaml
├─ pubspec.yaml
├─ lib/
│  ├─ main.dart
│  ├─ app.dart                       # MaterialApp.router, theme, routes
│  ├─ core/                          # pure Dart, no Flutter imports, fully unit-testable
│  │  ├─ ids.dart                    # UUID v7
│  │  ├─ money.dart                  # cents <-> text: parse, validate, format
│  │  ├─ date_range.dart             # presets + custom; default last30Days
│  │  ├─ bucketing.dart              # Day/Week/Month bucketing
│  │  └─ constants.dart              # kNoCategoryId, kNoPaymentMethodId, kMaxDepth, kWeekStartsOn
│  ├─ data/
│  │  ├─ database.dart               # AppDatabase, migrations, placeholder seed
│  │  ├─ tables.dart                 # Labels, Transactions
│  │  ├─ daos/{label_dao,transaction_dao}.dart
│  │  ├─ models/{transaction_filter,label_node,impacts,analytics_series}.dart
│  │  └─ repositories/{label_repository,transaction_repository}.dart
│  ├─ features/                      # each: <name>_screen.dart, <name>_providers.dart, widgets/
│  │  ├─ entry/                      # §2.2, §2.3
│  │  ├─ history/                    # §2.5–2.7
│  │  ├─ analytics/                  # §2.8
│  │  ├─ labels/                     # §2.4
│  │  ├─ export/                     # §2.9
│  │  └─ import/                     # Phase 9, post-v1 (parser lives in core/)
│  ├─ shared/
│  │  ├─ providers.dart              # database + repository providers (overridden in tests)
│  │  └─ widgets/
│  │     ├─ transaction_list.dart    # ← the §2.8.4 reuse point
│  │     ├─ transaction_tile.dart    # ← §2.6 needs-attention styling
│  │     ├─ label_picker.dart        # ← §2.2/§2.4 type-ahead, kind-parameterized
│  │     ├─ date_range_picker.dart
│  │     └─ confirm_dialog.dart      # ← the single confirmation primitive (§3.1)
│  └─ theme/theme.dart
└─ test/{core,data,widget}/
```

**Layering rule:** `core` imports nothing; `data` imports `core`; `features` import `data`/`core`/
`shared`; features never import each other — promote anything shared to `shared/`.

**No hand-written mapping layer.** drift's generated row classes *are* the domain model. Hand-written
models exist only for composites drift can't express (`TransactionWithLabels`, `LabelNode`,
`DeleteImpact`, `MoveImpact`, `AnalyticsSeries`).

### 3.1 Confirmation policy

Every destructive-or-structural action confirms first, through one shared `confirmDialog()` primitive.
Each confirmation states its **impact counts**, fetched via a `preview*` repository call (one `COUNT`).

| Action | Confirmation copy |
| --- | --- |
| Create label — inline, entry form (§2.4) | "Add 'X' as a new category?" |
| Create label — manage screen, nested | "Add 'X' under 'Parent'?" |
| Rename (§2.4) | "Rename 'Old' to 'New'? This updates the name on N past entries." |
| Move / reparent | "Move 'X' and its N sub-categories under 'Y'? Past entries are unchanged, but analytics rollups will shift." |
| Delete leaf (§2.4) | "Delete 'X'? N entries will move to No Category." |
| Delete parent (§2.4, §5) | "Delete 'X' and its N sub-categories? M entries will move to No Category." |
| Delete transaction (§2.3) | "Delete this transaction?" |
| Bulk recategorize (§2.5) | "Reassign N transactions to 'X'?" |

Move to top level uses the same dialog with "under Top level".

---

## 4. Build Order

Each phase is independently runnable and verifiable, and written to be handed to a **fresh session**.

**Session prompt template:** `Implement Phase N from docs/implementation-plan.md.`
(`CLAUDE.md` auto-loads; the phase brief names everything else it needs.)

Phase 2 precedes Phase 3 because the entry form depends on the label picker.

| Phase | Scope | Model / effort | Rationale |
| --- | --- | --- | --- |
| 0 | Scaffold | **Sonnet, low** | Mechanical: `flutter create`, deps, theme, router shell. |
| 1 | Data foundation | **Sonnet, medium** | Appendix B gives literal DDL; this is transcription + tests. |
| 2 | Labels | **Opus, high** | Hardest logic in the app: recursive CTEs, atomic cascade, depth-shift on move, cycle prevention. Spend here. |
| 3 | Entry form | **Sonnet, medium** | Standard form + validation against fixed contracts. |
| 4 | History & filters | **Sonnet, medium** | Dynamic query composition has sharp edges — if the filter tests fail twice, escalate to Opus medium. |
| 5 | Bulk recategorize | **Sonnet, medium** | Selection state + one atomic update. |
| 6 | Analytics | **Opus, medium** | Rollup + bucketing correctness. Charts alone would be Sonnet, but they share a session with the aggregation layer. |
| 7 | CSV export | **Sonnet, low** | Mechanical, and the filter logic is already built. |
| 8 | Platform hardening | **Opus, medium** | Open-ended platform debugging; poor fit for a cheap tier. |
| 9 | CSV import | **Opus, medium** | Added after v1, not in the spec. Label resolution and duplicate matching both have quiet failure modes that only show up on a second import. |

Fast mode is fine throughout — it doesn't downgrade the model.

---

### Phase 0 — Scaffold & rails (§2.10, §8)

**Preconditions:** empty repo containing only the spec.
**Create:** `pubspec.yaml` (Appendix A), `analysis_options.yaml` (strict lints), `lib/main.dart`,
`lib/app.dart`, `lib/theme/theme.dart`, `lib/core/constants.dart`.
`flutter create . --platforms=android,ios,windows`.
**Shell:** bottom nav **History | Analytics**; FAB on History → Add; app-bar overflow → Manage
Categories / Manage Payment Methods / Export.
**Accept:** `flutter analyze` clean; app launches on Android emulator **and** Windows desktop; all
nav destinations reachable with placeholder bodies.

> **Amended in Phase 3:** the shell became bottom nav **Add | History | Analytics**, with Add as the
> default tab and no FAB — see the Phase 3 brief below.

### Phase 1 — Data foundation (§2.2, §2.4, §2.10)

**Preconditions:** Phase 0.
**Create:** `lib/data/tables.dart` (**Appendix B verbatim**), `lib/data/database.dart` (schema v1,
indexes, placeholder seed at the Appendix-B UUIDs), `lib/core/{ids,money,date_range,bucketing}.dart`,
tests under `test/core/`.
**Contracts:** `Money.tryParse` handles `1,234.56` / `1234` / `.5` and rejects `0`, negatives, and
non-numerics. `DateRange.last30Days` is the default. `Bucket.{day,week,month}`; weeks are 7 days
starting `kWeekStartsOn` (Monday; one-line change to Sunday).
**Accept:** `dart run build_runner build` succeeds; `flutter test test/core` green; a fresh in-memory
DB contains exactly two placeholder rows; inserting `amount_cents = 0` or a blank `note` throws.

### Phase 2 — Categories & Payment Methods (§2.4) ⭐ hardest phase

**Preconditions:** Phase 1.
**Create:** `lib/data/daos/label_dao.dart`, `lib/data/repositories/label_repository.dart`,
`lib/data/models/{label_node,impacts}.dart`, `lib/features/labels/` (manage screen),
`lib/shared/widgets/{label_picker,confirm_dialog}.dart`.
**Contracts (Appendix C):** `create`, `rename`, `move`, `deleteCascade`, `previewDelete`,
`previewMove`, `subtreeIds`, `watchTree`, `search`.
**Rules to implement exactly:** depth cap via the move-validity math in §2; cascade delete =
resolve subtree → reassign referencing transactions to the placeholder → soft-delete subtree, all in
one `db.transaction`; placeholders reject rename/move/delete/parenting; move recomputes `depth` across
the subtree; sibling-name uniqueness enforced on create **and** move.
**UI:** manage screen tree with per-node actions Add sub-category / Rename / Move / Delete, each behind
§3.1 confirmation. `LabelPicker` is type-ahead, kind-parameterized, selectable at any level, and offers
"Add 'X' as a new category?" for unmatched text — **creating top-level only** (keeps the §1 fast path fast;
nesting happens on the manage screen, and move closes the loop).
**Accept:** `test/data/label_repository_test.dart` covers — cascade delete reassigns to placeholder;
depth cap rejects a 4th level; duplicate sibling rejected; move rejects a cycle; move rejects a
depth-overflow; move recomputes descendant depths; rename leaves transaction rows untouched;
placeholder mutations throw.

### Phase 3 — Entry, edit, delete (§2.2, §2.3)

**Preconditions:** Phase 2 (needs `LabelPicker`, `confirmDialog`).
**Create:** `lib/data/daos/transaction_dao.dart`, `lib/data/repositories/transaction_repository.dart`
(upsert/delete only for now), `lib/features/entry/`.
**Form, top to bottom:** amount (>0, `Money.tryParse`), payment-method picker, mandatory note,
category picker, date (defaults to now, freely editable to any date), optional extra notes. Amount
and payment method lead because those are the two things front-of-mind right after a purchase.
Delete behind §3.1 confirmation.
**Shell change:** `EntryScreen` gained an `embedded` flag and became the **Add** tab in the bottom
nav — `Add | History | Analytics`, replacing the original FAB-on-History pattern from Phase 0.
**Add is the default tab on launch**, since logging a transaction is the single most common action
and §1's fast-path goal favors landing straight on it rather than one tap away. Editing an existing
entry still routes through a separate pushed screen (`/entry/edit`, non-embedded, with the Delete
action) since History doesn't have list items to tap into yet — that wiring lands in Phase 4.
**Accept:** widget tests reject amount `0`, negative, and blank note; add → edit → delete round trip
persists; editing any field of a past entry works (§2.3); all three tabs (including Add) are
reachable, and Add is the tab shown on launch.

### Phase 4 — History & needs-attention (§2.6, §2.7, §5)

**Preconditions:** Phase 3.
**Create:** `lib/data/models/transaction_filter.dart`, `watchFiltered` on the repository,
`lib/features/history/`, `lib/shared/widgets/{transaction_list,transaction_tile,date_range_picker}.dart`.
**Rules:** newest-first default; all filters compose (AND, never exclusive); category filter offers the
placeholder as a normal value; search covers `note` **and** `extra_notes`; needs-attention styling is
derived, not stored; empty result renders an empty state and never falls back to unfiltered data (§5).
**Accept:** filter-composition tests (range ∧ category ∧ search) return the intersection; filtering to
"No Category" returns exactly the flagged entries; empty state renders.
→ **Mac checkpoint #1** — core loop on a real iOS device.

### Phase 5 — Bulk recategorization (§2.5)

**Preconditions:** Phase 4.
**Create:** `historySelectionProvider`, selection UI inside the existing list, `bulkReassign` on the
repository.
**Rules:** long-press enters selection mode **in the history list** — no separate screen (§2.5);
select-all-in-current-filter; reassign category and/or payment method in one atomic transaction,
behind §3.1 confirmation.
**Accept:** filter to "No Category" → select all → reassign → flags clear and the filtered list empties.

### Phase 6 — Analytics (§2.8)

**Preconditions:** Phase 5. Reuses the Phase 2 rollup CTE and the Phase 4 `TransactionList`.
**Create:** `lib/data/models/analytics_series.dart`, `watchSummary` on the repository,
`lib/features/analytics/`.
**Layout, top to bottom:** total → line chart (Day/Week/Month toggle, default Week per the Context
table) → bar chart by category (**Combined scope only**) → the reused `TransactionList`.
**Rules:** scope = single category at any level, or Combined; parent scope rolls up all descendants
automatically; line chart plots per-period totals, not a cumulative sum.
**Accept:** a parent's rollup total equals the sum of its subtree's transactions; bar chart absent for
single-category scope; bucket toggle re-buckets without refetching filters; a 5-day range defaults to
Day buckets. **Load the `dataviz` skill before writing chart code.**

> **As built.** Two provider details Phase 7 needs:
> - **Analytics has its own filter**, `analyticsFilterProvider` — it is *not* shared with
>   `historyFilterProvider`. The two views hold independent scope and range, so an export
>   triggered from Analytics must read the analytics filter, and one from History the history
>   filter. Exporting "the active filter" means *the calling view's* filter.
> - **Bucket resolution is split in two.** `analyticsBucketOverrideProvider` (nullable) holds the
>   user's explicit toggle; `analyticsBucketProvider` resolves it against the range-derived
>   default. Read the latter, set the former. This is what makes "the manual toggle always wins"
>   survive a later range change.
>
> Aggregation runs in Dart over the shared filtered query (see `watchSummary`), not a SQL
> `GROUP BY` — bucketing is local-time/calendar-aware, and sharing one query is what makes the
> total and the list beneath it structurally unable to disagree.

### Phase 7 — CSV export (§2.9)

**Preconditions:** Phase 6 (so both call sites exist).
**Create:** `lib/features/export/`.
**Rules:** serialize from the caller's active `TransactionFilter` — no independent filter logic. Share
sheet on mobile, save dialog on desktop. Amounts export as decimal strings, dates as ISO-8601 local.
Use `Money.toDecimalString` (already built) for amounts — never format cents by hand, and never
`Money.format`, which is locale-currency output for the UI, not CSV.
**Which filter:** History and Analytics hold **separate** filter providers (see the Phase 6 "As
built" note). Export from whichever view invoked it; there is no single global filter.
**Accept:** exporting from a filtered view yields exactly that filtered set; exporting from an empty
filtered view yields a header-only file, not all data.

> **As built.** The original shell had a single global `/export` placeholder route reached from the
> app-bar overflow menu — but that can't express "the invoking view's filter" (there is no global
> filter, per the Phase 6 note above). Replaced with an **export icon button directly in the shell's
> app bar**, shown only on the History and Analytics tabs, each reading that tab's own
> `historyFilterProvider` / `analyticsFilterProvider`. The overflow menu now holds only the two
> Manage entries. `lib/features/export/` holds `csv_export.dart` (pure serialization, unit-tested)
> and `export_service.dart` (the platform hand-off); `export_action.dart` is the shared glue the two
> screens' app-bar buttons call into.

### Phase 8 — Platform hardening (§2.10)

**Preconditions:** Phases 0–7.
Windows desktop pass. Perf check against ~5k seeded rows (list scroll, analytics query). Manual-backup
guidance in the README.
→ **Mac checkpoint #2** — full iOS pass, sideload / SideStore path per §8.

**Carried-in findings** (observed during Phase 6, deliberately not fixed there):

1. **`flutter build windows` can fail on missing `windows/flutter/ephemeral/` C++ wrapper files**
   (`core_implementations.cc`, `standard_codec.cc`, …) with `error C1083: Cannot open source file`.
   This is stale scaffold state, not a code defect — `flutter clean && flutter pub get` regenerates
   them and the build succeeds. Don't go hunting in `windows/` for a real cause.
2. **Analytics aggregates in Dart, not SQL.** Correct and deliberate for a personal dataset
   (thousands of rows), but it is the one place that scales with row count rather than with what's
   on screen. The ~5k-row perf check should measure the analytics query specifically; if it drags,
   the fix is a SQL `GROUP BY` for the *totals only*, keeping local-time bucket boundaries computed
   in Dart and passed in as range bounds.
3. **`TransactionList` renders unvirtualized inside Analytics** (`shrinkWrap: true` +
   `NeverScrollableScrollPhysics`, since it sits in an outer `ListView`). Every filtered row builds,
   so a wide date range on a large dataset builds every tile. History is unaffected — it scrolls
   normally and virtualizes. If the 5k-row check shows this, cap the analytics list (e.g. "showing
   50 of N, view all in History") rather than un-nesting the scroll view.

> **As built.**
>
> **The perf check found a hang, not a slowdown — and it was a correctness bug.**
> `bucketEnd` advanced day/week buckets with `start.add(Duration(days: 1))`. On a DST *fall-back*
> date the local day is 25 hours long, so that landed at 23:00 on the **same** date; `bucketStart`
> then floored it straight back to the same midnight. `_fillGaps` steps
> `cursor = bucketStart(bucketEnd(cursor))`, so the cursor stopped advancing and the loop appended
> `BucketPoint`s forever. Any user whose Analytics range spanned a fall-back date with Day buckets
> would hang the app — an unkillable spin, not a slow query. It went unnoticed until Phase 8
> because every prior test used ranges of days-to-weeks that happened to miss the transition.
>
> Fixed by advancing with calendar arithmetic (`DateTime(y, m, d + 1)`), which normalizes overflow
> and always lands on the next local midnight regardless of offset changes. `bucketStart`'s week
> case had the same latent flaw (`subtract(Duration(days: diff))`) and got the same treatment.
> `_fillGaps` now throws a `StateError` if a bucket step ever fails to advance — the guarantee is
> cheap to assert and the cost of being wrong is an unkillable UI. Regression tests live in
> `test/core/bucketing_test.dart` under `group('DST safety')`; they assert the always-advances
> invariant, which holds in **every** timezone, so they stay meaningful on a runner with no DST.
>
> **Perf itself was a non-issue.** At 5k rows (`test/data/perf_test.dart`, tagged `perf`, seeded by
> `test/data/seed_dataset.dart`): history query ~277ms, analytics combined/month ~446ms, analytics
> rollup/day ~136ms, text search ~45ms, needs-attention filter ~14ms. Carried-in finding 2 (Dart
> aggregation) needs no action — the SQL `GROUP BY` fallback stays unbuilt.
>
> **The perf assertions are ratios, not wall-clock budgets** — worth knowing before "fixing" them.
> Absolute millisecond budgets were tried first and failed spuriously when the suite ran alongside
> `flutter analyze` (the same query: 818ms contended, 524ms idle). A calibration against a *single-row*
> lookup was tried next and was worse — a query returning no rows doesn't slow proportionally under
> load, so the ratio swung 400x→1450x. What works is calibrating against a **bare 5000-row
> `SELECT`**: both sides read the same rows, so contention scales them together. Verified stable
> across idle and doubly-loaded runs (history 3.0–4.1x, rollup/day 2.1–2.8x). If these ever need
> retuning, re-measure the ratio under load rather than raising a constant.
>
> **Carried-in finding 3 was fixed as prescribed.** `TransactionList` gained an opt-in `maxItems`
> plus `overflowFooterBuilder`; Analytics passes 50 and a footer naming the true total. History
> passes neither and is unchanged — it virtualizes, so capping it would only hide data. The total,
> charts, and CSV export still read the full filtered set, so the headline can't disagree with what
> the cap hides.
>
> **Carried-in finding 1 did not reproduce** — `flutter build windows` succeeded without needing
> `flutter clean`. Kept in the README as a troubleshooting note.
>
> **Also fixed:** the desktop CSV path wrote `Uint8List.fromList(csv.codeUnits)`, truncating UTF-16
> units to bytes and corrupting any non-ASCII note or label name. Now `utf8.encode`, with the
> mobile path pinned to `encoding: utf8` too.
>
> **Backup guidance** landed in the README and the user guide. Worth recording: `drift_flutter`
> 0.3.1 resolves `driftDatabase(name:)` via **`getApplicationDocumentsDirectory()`**, not app
> support — so on Windows the file is `Documents\spending_tracker.sqlite` (verified on disk, not
> assumed). That file-copy restore path exists only on desktop; on mobile it's in private app
> storage, which is why CSV export is the answer there.

### Phase 9 — CSV import (post-v1 addition)

**Not in the spec.** §2.9 asks only for export; import was requested afterwards, and the spec is
locked, so this is recorded as a deliberate addition rather than a reinterpretation. It does not
touch any §6 non-goal except duplicate detection, discussed below.

**Preconditions:** Phase 7 (the export format is the import format).
**Create:** `lib/core/csv_import.dart` (pure parser), `lib/data/models/import_plan.dart`,
`lib/data/daos/import_dao.dart`, `lib/features/import/`
(`import_service.dart`, `duplicate_dialog.dart`, `import_action.dart`).

**Shape of the feature.** Import is **preview-then-commit**: parse → resolve against the DB →
confirm with real counts → answer every duplicate → one atomic write. Nothing is written until the
user has seen the counts, and a failure rolls back rows *and* the labels created for them.

**What the export format cannot carry**, which defines the feature's limits:

- **No transaction id.** An imported row is always a new row; identity-based dedup is impossible.
- **No label path.** Export writes a label's own name, so `Food > Restaurants` exports as
  `Restaurants`. Missing labels are therefore created **top-level**, matching the entry picker's
  fast path; nesting is rebuilt via `move` on the manage screen. An ambiguous name (same name under
  two parents) resolves shallowest-first, then by id, so resolution is deterministic.

**Duplicate detection — a deliberate, scoped exception to §6.** §6 rules out automatically
detecting duplicates. That guardrail is about the *entry* path: the app must not second-guess the
user as they log purchases. On the import path, the absence of any check means re-importing a file
silently doubles the user's history — so import compares **every field the CSV carries**
(occurred-at millis, amount cents, category name, payment method name, note, extra notes) and
prompts per match. Time is part of the key on purpose: two identical purchases on the same day are
real and must stay distinct. Nothing about the entry path changed.

The prompt is modelled on a file-copy conflict: **Keep both / Replace / Skip / Cancel import**, with
a "do this for the remaining N" checkbox. An unanswered duplicate defaults to keep-both — the
choice that never loses data.

**Blank label cells resolve to the placeholder** and import flagged as needs-attention (§2.6).
This is subtle enough to have been a real bug: the stored row reads `No Category` while the
incoming cell is `''`, so matching on raw text re-imported the row as new on every pass and an
export/import loop grew without bound. Matching compares the name the row *resolves to*. Regression
tests: `group('duplicate detection')` in `test/data/import_test.dart`.

**No filter.** Import takes no `TransactionFilter` — a filter narrows what leaves the app, and
there is nothing to narrow on the way in. It therefore lives in the **overflow menu**, global, not
beside the per-view export icon.

**No schema change.** `ImportDao` is a new accessor over the existing tables; `schemaVersion` stays
at 1 and the migration harness is untouched.

**iOS-clean.** Reading goes through `file_selector`'s `openFile` on every platform — the share
sheet exists because iOS gives an app nowhere to *write*, which doesn't apply to reading. A UTF-8
BOM is stripped so a file round-tripped through Excel still passes the header check.

**Accept:** parser rejects a non-export header; a bad row is skipped with its line number while
good rows import; a re-imported export reports every row as a duplicate and skip-all is a no-op;
label names match case-insensitively and are created once per file; a failed commit leaves no rows
**and** no labels. Covered by `test/core/csv_import_test.dart` (18),
`test/data/import_test.dart` (28), `test/widget/duplicate_dialog_test.dart`,
`test/widget/import_action_test.dart`.

---

## 5. Remaining Assumptions

1. **Weeks start Monday** (`kWeekStartsOn` — one-line change to Sunday).
2. **Line chart plots per-period totals**, not a cumulative running sum ("how am I trending", §2.8).
3. **Currency formats from the device locale** via `intl`. Multi-currency is a §6 non-goal, so there's
   no currency column and no setting.
4. **Sort order within a label's siblings is alphabetical** by default; `sort_order` exists in the
   schema for future manual ordering but isn't surfaced in v1.

---

## 6. Verification

- `flutter analyze` clean and `flutter test` green at every phase boundary.
- `docs/user-guide.md` updated at every phase boundary: move the phase's features out of its
  "Not built yet" table and document the real behaviour, limits included.
- Repository tests run against an **in-memory drift DB** (`databaseProvider` overridden) — no mocks for
  DB behavior, since cascade/rollup/move correctness *is* SQL behavior.
- `drift_dev schema dump` + generated migration tests. The on-device DB is the user's only copy —
  there is no server backup — which makes migration safety unusually important.
  **Status:** the harness was actually built during Phase 2, not Phase 1 (`drift_schemas/`,
  `test/data/generated_migrations/`, `test/data/migration_test.dart`). Nothing was missed in the
  interim — Phase 2 added no schema changes, so the DB is still v1. See CLAUDE.md
  "Schema migrations" for the per-change workflow. Note this needs `drift_dev` ≥ 2.34.5; 2.34.0
  does not compile against `drift` 2.34.3.
- End-to-end smoke per phase on Android emulator + Windows desktop; iOS at the two Mac checkpoints.

---

## Appendix A — Dependencies

```yaml
dependencies:
  flutter: {sdk: flutter}
  drift: ^2.28.0
  drift_flutter: ^0.3.1
  flutter_riverpod: ^2.6.0
  go_router: ^14.0.0
  fl_chart: ^1.2.0
  intl: ^0.20.0
  uuid: ^4.5.0
  csv: ^6.0.0
  share_plus: ^10.0.0
  path_provider: ^2.1.0
  file_selector: ^1.0.0

dev_dependencies:
  flutter_test: {sdk: flutter}
  drift_dev: ^2.34.5   # must be >= 2.34.5: 2.34.0 won't compile against drift 2.34.3
  build_runner: ^2.4.0
  flutter_lints: ^5.0.0
```

Resolve to current stable at scaffold time; the majors above are the intent.

## Appendix B — Table definitions (`lib/data/tables.dart`)

```dart
import 'package:drift/drift.dart';

enum LabelKind { category, paymentMethod }

class Labels extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<LabelKind>()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Labels, #id)();
  IntColumn  get depth => integer()();                    // 0..2
  BoolColumn get isPlaceholder => boolean().withDefault(const Constant(false))();
  IntColumn  get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn  get createdAt => integer()();                // UTC epoch ms
  IntColumn  get updatedAt => integer()();
  IntColumn  get deletedAt => integer().nullable()();

  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => [
    'CHECK (depth BETWEEN 0 AND 2)',
    'CHECK (length(trim(name)) > 0)',
  ];
}

class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn  get amountCents => integer()();
  IntColumn  get occurredAt => integer()();               // UTC epoch ms, user-editable
  TextColumn get categoryId => text().references(Labels, #id)();
  TextColumn get paymentMethodId => text().references(Labels, #id)();
  TextColumn get note => text()();
  TextColumn get extraNotes => text().nullable()();
  IntColumn  get createdAt => integer()();
  IntColumn  get updatedAt => integer()();
  IntColumn  get deletedAt => integer().nullable()();

  @override Set<Column> get primaryKey => {id};
  @override List<String> get customConstraints => [
    'CHECK (amount_cents > 0)',
    'CHECK (length(trim(note)) > 0)',
  ];
}
```

Indexes and the partial unique index are declared in `database.dart`'s migration via
`customStatement`, since drift's table API doesn't express partial indexes:

```sql
CREATE UNIQUE INDEX ux_labels_sibling
  ON labels (kind, IFNULL(parent_id,''), name) WHERE deleted_at IS NULL;
CREATE INDEX ix_labels_parent   ON labels (kind, parent_id);
CREATE INDEX ix_tx_occurred     ON transactions (occurred_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_tx_category     ON transactions (category_id);
CREATE INDEX ix_tx_payment      ON transactions (payment_method_id);
```

**Seeded placeholder UUIDs** (fixed forever — referenced from `core/constants.dart`):

```dart
const kNoCategoryId      = '00000000-0000-7000-8000-000000000001';
const kNoPaymentMethodId = '00000000-0000-7000-8000-000000000002';
const kMaxDepth = 2;   // 0-indexed → 3 levels
```

## Appendix C — Name inventory

Fixed so phases built in separate sessions don't invent divergent names.

```dart
// lib/data/repositories/label_repository.dart
Stream<List<LabelNode>> watchTree(LabelKind kind);
Future<List<Label>>     search(LabelKind kind, String query);
Future<Label?>          findByName(LabelKind kind, String name, {String? parentId});
Future<Label>           create({required LabelKind kind, required String name, String? parentId});
Future<RenameImpact>    previewRename(String id);
Future<void>            rename(String id, String newName);
Future<MoveImpact>      previewMove(String id, String? newParentId);
Future<void>            move(String id, String? newParentId);
Future<DeleteImpact>    previewDelete(String id);
Future<void>            deleteCascade(String id);
Future<Set<String>>     subtreeIds(String id);

// lib/data/repositories/transaction_repository.dart
Stream<List<TransactionWithLabels>> watchFiltered(TransactionFilter f);
Future<List<TransactionWithLabels>> listFiltered(TransactionFilter f);   // export
Stream<AnalyticsSummary>            watchSummary(TransactionFilter f, Bucket bucket);
Future<void>                        upsert(TransactionDraft d);
Future<void>                        delete(String id);
Future<void>                        bulkReassign({required Set<String> ids,
                                                  String? categoryId, String? paymentMethodId});
Future<void>                        bulkDelete(Set<String> ids);
Future<ImportPlan>                  planImport(ImportParseResult parsed);      // read-only
Future<ImportResult>                commitImport(ImportPlan p,
                                                 Map<int, DuplicateChoice> choices);

// lib/core/csv_import.dart — pure, no Flutter/DB
CsvImport.parse(String csv) -> ImportParseResult   // throws ImportFormatException
class ImportRow    { lineNumber, occurredAt, amountCents, categoryName,
                     paymentMethodName, note, extraNotes }
class ImportRowError     { final int lineNumber; final String message; }
class ImportParseResult  { final List<ImportRow> rows; final List<ImportRowError> errors; }

// models
class DeleteImpact { final int descendantCount; final int affectedTransactionCount; }
class MoveImpact   { final int subtreeCount; final bool valid; final String? reason; }
class RenameImpact { final int affectedTransactionCount; }
class AnalyticsSummary { final int totalCents; final List<BucketPoint> series;
                         final List<CategoryTotal> byCategory; }
enum  DuplicateChoice  { keepBoth, skip, replace }
class DuplicateCandidate { final ImportRow row; final Transaction existing; }
class ImportPlan   { final List<ImportRow> newRows; final List<DuplicateCandidate> duplicates;
                     final List<ImportRowError> errors;
                     final Set<String> newCategoryNames, newPaymentMethodNames; }
class ImportResult { final int inserted, replaced, skipped, labelsCreated;
                     final List<ImportRowError> errors; }

// providers — all live in lib/shared/providers.dart (no feature-local provider
// files were needed; keep new ones here so cross-feature reuse stays possible)
databaseProvider · labelRepositoryProvider · transactionRepositoryProvider
labelTreeProvider(LabelKind)                       // family
historyFilterProvider · historyTransactionsProvider · historySelectionProvider
historyVisibleSelectionProvider                    // selection ∩ visible rows; act on THIS
analyticsFilterProvider · analyticsBucketProvider · analyticsSummaryProvider
analyticsBucketOverrideProvider                    // nullable; user's explicit toggle
analyticsTransactionsProvider                      // the §2.8.4 reused list
```

Two additions beyond the original plan, both load-bearing:
`historyVisibleSelectionProvider` (bulk writes must not touch rows the filter hides) and
`analyticsBucketOverrideProvider` (separating the user's toggle from the resolved bucket is what
lets "the manual toggle always wins" survive a later range change). Read
`analyticsBucketProvider`, but write `analyticsBucketOverrideProvider`.

---

## 7. Draft `CLAUDE.md`

Written to the repo root as `CLAUDE.md`. Reproduced here so this document stays self-contained.

> **This is the original Phase-0 draft, kept for reference. `CLAUDE.md` at the repo root is the
> live version and has since moved ahead of it** (toolchain versions, the `drift_dev` pin, and the
> "Schema migrations" workflow added in Phase 2). Read the root file, not this copy.

````markdown
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
````
