# Personal Spending Tracker — Product Specification

## 1. Problem Statement

The user wants an easy, low-friction way to manually log personal spending
(cash, Venmo, card, or any other payment method) and understand their
spending trends over time — how much they're spending, where, and when.
The core risk to solve for is that manual entry must be fast enough to
become an automatic habit, without losing meaningful detail about each
transaction.

## 2. Confirmed Requirements

### 2.1 Users & Scope
- Single-user application. No accounts, login, or authentication required.
- Data is local to a single device — no multi-device sync in this version.
- The app may later be distributed to other individuals (friends/family),
  but each person's app instance and data is entirely separate and private
  to them. There is no shared or multi-user data model.

### 2.2 Transaction Entry
Every transaction has the following fields:

**Required:**
- **Amount** — manual numeric entry. Must be strictly greater than 0. No
  upper bound.
- **Date** — defaults to the current date/time at entry creation, but is
  editable to any date.
- **Category** — selected from a user-defined, reusable list (see 2.4).
- **Payment Method** — selected from a user-defined, reusable list (see
  2.4).
- **Transaction Note** — a short, mandatory label describing what the
  transaction was (e.g., "Lunch with Sam"). No length restriction enforced,
  but intended to be brief.

**Optional:**
- **Additional Notes** — longer free-text field for extra context (e.g.,
  "split 3 ways, I paid for everyone"). No length restriction.

Category and Payment Method fields are implemented as type-ahead dropdowns
showing the user's existing, previously-used values as they type, to keep
entry fast.

### 2.3 Editing & Deleting Entries
- Any field on any past entry can be edited freely.
- Deleting an entry requires user confirmation before the deletion is
  finalized (a confirmation prompt/step, not an immediate irreversible
  delete).
- No audit trail or edit history is kept.

### 2.4 Categories & Payment Methods
- Both Categories and Payment Methods are freeform: the user defines and
  reuses their own values rather than choosing from a fixed preset list.
- Both support **nesting, up to a maximum of 3 levels deep** (e.g.,
  Food > Restaurants > Fast Food).
- At entry time, the user may select a category/payment method at **any
  level** of the hierarchy — a parent, without being forced to pick a more
  specific child (no auto-created child selections; selecting "Food" saves
  the entry directly under "Food").
- **Creating new values:** when a user types a new category or payment
  method name that doesn't already exist, they are shown a confirmation
  step ("Add 'X' as a new category?") before it's created and added to the
  reusable list.
- **Renaming:** renaming a category or payment method updates the display
  name on all past entries that reference it (the rename cascades).
- **Deleting a parent with children:** deletion cascades — the parent and
  all of its sub-categories/sub-payment-methods are deleted together (no
  option to delete a parent while keeping orphaned children as top-level
  items).
- **Deleting a category/payment method that's in use:** any entries that
  referenced the deleted value are reassigned to a special **"No
  Category"** / "No Payment Method" placeholder value, and are visually
  flagged as needing attention (see 2.6).

### 2.5 Bulk Recategorization
- From the transaction history list, the user can multi-select entries
  (directly in that list — no separate dedicated screen) and reassign
  their category (and/or payment method) in one action, rather than
  editing each entry individually.

### 2.6 "Needs Attention" Flagging
- Entries whose Category or Payment Method was deleted (and are now set to
  "No Category" / "No Payment Method") are visually distinguished in the
  normal transaction history list (e.g., color or icon), no separate
  dedicated view required.
- **"No Category"** (and equivalently "No Payment Method") is itself a
  selectable filter value in the category/payment-method filter — allowing
  the user to filter the history list down to exactly the entries needing
  recategorization, then bulk-recategorize them per 2.5.

### 2.7 Transaction History View
- Displays all transactions, **newest first by default**.
- Filterable by:
  - Date range — sensible defaults provided, but a custom user-selected
    range is always available.
  - Category (including the "No Category" placeholder as a filter option).
  - Text search — searches both the Transaction Note and Additional Notes
    fields.
- All filters (date range, category, text search) are composable — they
  apply together, on top of one another, not exclusively.
- Supports the multi-select bulk recategorization described in 2.5.

### 2.8 Spending Analytics View
Kept as a distinct view from the raw Transaction History (2.7), for
answering "how am I trending" rather than "what did I buy."

- User selects either:
  - A **single category** (at any level of the hierarchy), or
  - **"Combined"** — spending across all categories.
- User selects a date range — sensible defaults provided, custom range
  always available.
- Once selected, the view displays, top to bottom:
  1. **Total spending amount** for the selected scope and date range.
  2. **Line graph** of spending over time within that range.
  3. **Bar chart breakdown by category** — shown **only** when "Combined"
     is selected (not shown for a single-category view, since there's
     nothing to break down).
  4. **Scrollable transaction list** matching the selected scope/date range
     (i.e., the same filtered list behavior as the Transaction History
     view, reused here rather than duplicated).
- **Category rollup:** when a parent category is selected (in either the
  single-category or combined view), its total and charts include the
  spending of all of its nested sub-categories automatically.

### 2.9 Data Export
- The user can export their transaction data to a **CSV file** as a manual
  backup / data-safety hedge (there is no automatic backup, since there is
  no server/account).
- Export **respects whatever filters are currently active** in the view
  it's triggered from (e.g., exporting from a filtered "this month, Food
  category" view exports just that filtered set), rather than always
  exporting all data unconditionally.

### 2.10 Platform
- Must work as a usable app on **iOS and Android**, built and maintained
  as effectively separate builds/experiences per platform (not necessarily
  one shared codebase — that decision is deferred to the implementation
  phase and intentionally not specified here).
- Desktop (Windows/Mac) support is a **nice-to-have**, not required for v1.
- No multi-device sync in this version — each device's data is
  self-contained and independent. However, multi-device sync is a desired
  future direction (not part of this version's scope), so implementation
  should favor approaches that keep the barrier to adding sync later low,
  where doing so doesn't conflict with any other confirmed requirement
  above.

## 3. Assumptions & Recommendations

*(Everything below is a recommendation or assumption, not something
explicitly confirmed by the user — flagged separately per process.)*

- No specific recommendation is made here on framework/tech stack (Flutter,
  PWA, or otherwise) — this was intentionally discussed but deliberately
  left out of this spec as an implementation-phase decision.
- It's assumed the app needs no onboarding/tutorial flow beyond the
  in-context confirmation step for creating new categories/payment
  methods, since no such flow was discussed.
- It's assumed default date ranges (mentioned in 2.7 and 2.8) can be
  something standard like "This Month" — the exact default was not
  specified by the user and should be confirmed or decided at
  implementation time.
- It's assumed the line graph in Analytics (2.8) plots daily or
  period-bucketed totals rather than a raw per-transaction plot, but the
  exact granularity/bucketing was not specified and should be confirmed at
  implementation time.

## 4. Features & Characteristics

Covered in full behavioral detail under Section 2 above (Confirmed
Requirements), which doubles as the feature specification per the
process for this document.

## 5. Edge Cases & How They're Handled

- **Amount of 0 or negative:** rejected — entry cannot be saved (2.2).
- **Category/Payment Method deleted while in use:** all referencing
  entries reassign to "No Category"/"No Payment Method" and are flagged as
  needing attention in the history list (2.4, 2.6).
- **Deleting a parent category/payment method with children:** children
  are deleted along with the parent (cascade); any entries referencing the
  parent or any of its children become "No Category" and are flagged
  (2.4).
- **Renaming a category/payment method:** all past entries referencing it
  display the new name; nothing is orphaned (2.4).
- **Selecting a parent category at entry time (not a specific child):**
  allowed and saved as-is; no auto-created child category is generated
  (2.4).
- **Viewing analytics for a parent category:** includes rollup of all
  nested sub-category spending automatically (2.8).
- **Duplicate entries (e.g., same purchase logged twice):** no automatic
  detection; user must notice and manually fix/delete (explicit non-goal,
  Section 6).
- **No data/entries matching current filters:** implicitly, filtered views
  (history, analytics, export) should reflect an empty result rather than
  falling back to unfiltered data — exact empty-state presentation left to
  implementation.

## 6. Explicit Non-Goals

This product deliberately does **not**, in this version:
- Support multiple users or shared/collaborative data of any kind.
- Sync data automatically across multiple devices.
- Support multiple currencies.
- Track income, refunds, or any money coming in — expense-only.
- Maintain an edit/change audit trail on transactions.
- Enforce a minimum or maximum bound on transaction amount (beyond >0).
- Automatically detect or warn about likely duplicate entries.
- Integrate with banks or any external financial data source (all entry is
  manual, by design).
- Include a dedicated screen/view solely for flagged "needs attention"
  entries beyond the "No Category" filter option.

## 7. Open Questions

- Exact default date range(s) for History and Analytics views (see
  Section 3 — flagged as an assumption needing confirmation).
- Exact time-bucketing/granularity for the Analytics line graph (see
  Section 3 — flagged as an assumption needing confirmation).

## 8. Framework Decision Note

Candidates considered: **Flutter**, **PWA**, **Flet** (Python/Flutter),
and **React Native** (ruled out early — no React experience).

- **PWA** was attractive for zero-friction install (Add to Home Screen,
  no Apple Developer account) and free desktop support, but iOS Safari's
  storage model (IndexedDB eviction risk, historical stability bugs) is a
  poor fit for a long-term financial record, and fully eliminating
  "web-page" tells (scroll bounce, tap-highlight flash, keyboard jank) is
  hard — a real concern given the app's core goal of frictionless,
  habitual entry.
- **Flet** was appealing given Python comfort, but was set aside once it
  was confirmed that understanding/reviewing the underlying code isn't a
  priority — Flutter is better-established and more reliably implemented
  by an AI coding assistant.
- **iOS distribution overhead**, initially a concern for Flutter, is
  manageable without a paid Apple Developer account: free Xcode
  sideloading (7-day re-sign limit) combined with SideStore reduces this
  to near-zero ongoing effort. Android sideloading is frictionless
  either way.

**Decision: Flutter.** True native feel, robust local SQLite storage,
and free desktop/mobile builds from one codebase, with an acceptable,
low-cost path to iOS installation outside the App Store. Implementation
to proceed via Claude Code.
