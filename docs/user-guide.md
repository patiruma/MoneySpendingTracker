# Spending Tracker — User Guide

A personal expense tracker that runs entirely on your device. No account, no sign-in, no server.
Your data never leaves your phone or computer.

> **Status: feature-complete for v1** on Android and Windows. Everything described below works
> today; the only outstanding work is an iOS pass, which needs a Mac. Last updated at the end of
> Phase 8 (platform hardening).

---

## The idea in one paragraph

You log what you spend, tagging each entry with a **Category** (what it was for) and a **Payment
Method** (how you paid). Both are lists you build yourself as you go — there's no fixed set to
choose from. Later you can filter and chart that history to see where your money is going.

Categories and Payment Methods work **identically** in every respect described below. Anything
this guide says about one is true of the other.

---

## Categories & Payment Methods

Reach these from the **⋮ overflow menu** in the top-right: *Manage Categories* or
*Manage Payment Methods*.

Each entry in the list has a **⋮ menu** with four actions: **Add sub-category**, **Rename**,
**Move**, and **Delete**. The **Add** button at the bottom creates a new top-level item.

### Nesting

You can organize labels up to **3 levels deep**:

```
Food                    ← level 1
  └─ Restaurants        ← level 2
       └─ Fast Food     ← level 3
```

Three levels is a hard limit. There is no 4th level, and the app blocks the attempt rather than
silently flattening it.

When logging an entry you can pick a label at **any** level. Choosing "Food" saves the entry under
"Food" — you're never forced down to a specific sub-item, and picking a parent doesn't secretly
create a child.

### Renaming

Renaming updates the name **everywhere**, including on every past entry that used it. Rename "Food"
to "Groceries" and your entire history follows along — nothing is orphaned or left behind. The
confirmation tells you how many past entries are affected before you commit.

### Moving (re-parenting)

**Move** relocates a label somewhere else in the tree — including to **Top level**. Anything nested
underneath travels with it.

Moving never changes your past entries: they stay attached to the same label. What *does* change is
how spending rolls up in Analytics, since the label now reports under a different parent. The
confirmation says so.

A move is rejected when it doesn't fit:

- **It would exceed 3 levels.** This depends on the whole branch, not just the item you're moving.
  A single label can slot into a level-2 spot; a label with its own children may not fit the same
  spot, because its children need room below it.
- **It would create a loop** — you can't move a label into itself or into one of its own
  sub-items.
- **A label with that name already exists there.**

The destination list only offers places that actually work, so you generally won't hit these. If
you do, the app explains which rule applied.

### Deleting

Deleting **cascades**: the label and everything nested under it go together. There's no option to
delete a parent while keeping its children as standalone items.

Entries that used any deleted label aren't lost. They're reassigned to **"No Category"** (or
**"No Payment Method"**) and flagged so you can find and re-file them later. The confirmation tells
you up front how many sub-items and how many entries will be affected.

Deleting a **child** leaves its parent and the parent's own entries completely untouched.

After deleting, the name is free again — you can immediately create a new label with the same name.

### "No Category" and "No Payment Method"

These two are built in and always present. They're where entries land when the label they were
using gets deleted, which is how you find entries needing attention.

They can't be renamed, moved, deleted, or used as a parent — so they show no ⋮ menu at all. That's
deliberate: they're the safety net, so they always have to exist.

### Naming rules

- Two items **under the same parent** can't share a name (capitalization doesn't make them
  different — "Food" and "food" collide).
- The same name **under different parents** is fine: `Food > Misc` and `Travel > Misc` coexist.
- The same name in **Categories and Payment Methods** is fine — they're separate lists.
- Names can't be blank.

### Quick reference

| You want to… | Allowed? | Where |
| --- | --- | --- |
| Nest up to 3 levels | ✅ | Manage screen → ⋮ → Add sub-category |
| Nest a 4th level | ❌ blocked | — |
| Pick a parent label when logging | ✅ | Entry form |
| Rename anything (cascades to past entries) | ✅ | Manage screen → ⋮ → Rename |
| Move a label, children included | ✅ | Manage screen → ⋮ → Move |
| Move a label into its own sub-item | ❌ blocked | — |
| Move a branch somewhere it doesn't fit | ❌ blocked | — |
| Delete a parent but keep its children | ❌ cascades instead | — |
| Reuse the name of a deleted label | ✅ | — |
| Duplicate names under the same parent | ❌ blocked | — |
| Duplicate names under different parents | ✅ | — |
| Rename/move/delete "No Category" | ❌ built in | — |
| Reorder items by hand | ❌ not in this version | sorted alphabetically |

---

## Logging a transaction

**Add** is the app's default tab — it's what you see when you open the app, and it's also the
first destination in the bottom nav, alongside **History** and **Analytics**. The form, top to
bottom:

- **Amount** — required, must be greater than 0. Typing `0`, a negative number, or leaving it
  blank is rejected right there in the form.
- **Payment Method** — the same type-ahead picker used everywhere else in the app. Pick an
  existing value at any level of nesting, or type a new name and confirm "Add 'X' as a new payment
  method?" to create one on the spot. New values created this way are always **top-level** —
  nesting an entry's label happens later, on the Manage screen.
- **Note** — required, a short description of what the transaction was for.
- **Category** — same picker behavior as Payment Method above.
- **Date** — defaults to right now, but you can pick any date and time, past or future.
- **Additional notes** — optional, for longer context.

Amount and Payment Method lead the form since those are usually the two things front-of-mind right
after a purchase. There's no confirmation step to save a transaction — logging is meant to be fast
enough to become a habit, so only structural changes (renaming, moving, deleting a *label*) ask
first. After saving, the form clears itself so you can log the next entry right away.

## Editing and deleting an entry

Tap any entry in the **History** list to open its Edit screen, where you can change **any**
field — amount, date, category, payment method, note, or additional notes. There's no limit on
how far back you can edit, and no history is kept of what it used to say.

Deleting a transaction **does** ask first — "Delete this transaction?" — since unlike logging, an
accidental delete can't be walked back by re-typing it.

### Changing an entry's category vs. renaming a category

Worth separating, because it's a different thing in a different place:

- **Changing which category an entry uses** happens on the entry itself — edit that one
  transaction, or long-press to multi-select several in **History** and reassign them at once
  (see below).
- **Renaming a category** happens on the **Manage** screen and affects every entry using it.

The short version: the Manage screen changes *what a label is called*. Editing an entry changes
*which label that one entry points at*. The Manage screen never edits your entries.

---

## Bulk recategorizing entries

From **History**, long-press any entry to enter selection mode, right there in the list — there's
no separate screen for this. The filter bar is replaced by a selection bar showing how many
entries are selected, with three actions:

- **✕** — clears the selection and returns to the normal filtered view.
- **Select all** — selects every entry currently matching your active filters (not necessarily
  everything in your history — whatever the list is showing at the time).
- **Reassign** — opens a sheet to pick a new Category and/or new Payment Method. Leaving either
  one unset keeps that field as-is on every selected entry; setting both changes both.

Tapping any entry while in selection mode toggles it in or out of the selection, instead of
opening it for editing. After choosing what to reassign to, you'll see a confirmation stating how
many entries are affected before anything is written — reassignment is a bulk write, so it goes
through the same confirmation policy as other structural changes.

A common flow: tap the **Needs attention** chip to filter down to "No Category" entries, long-press
one, **Select all**, then **Reassign** them to their real category in one action. Once reassigned,
they no longer match the "Needs attention" filter and drop out of that view immediately.

---

## Finding entries: the History list

**History** shows every transaction, **newest first**. Above the list are the filters, and all of
them combine — turning on more than one narrows the list further, they never override each other:

- **Search notes** — matches text against both the Note and Additional notes fields, not just one.
- **Date range** — defaults to the **last 30 days**. Presets (last 7 days, last 30 days, this
  month) are one tap away via the dropdown next to the range; you can also tap the range itself to
  pick any custom start and end date.
- **Category** and **Payment method** — pick any label at any level, including "No Category" /
  "No Payment Method" themselves. Selecting a parent shows that parent's entries plus everything
  under it — the picker doesn't limit you to exact matches.
- **Needs attention** — a shortcut chip that's equivalent to setting the Category filter to
  "No Category" directly; toggling it off clears that filter.

If no entry matches the current combination of filters, the list shows an empty-state message
rather than quietly falling back to showing everything. That's deliberate — an empty result is
information (nothing matches), not an error to work around.

### Needs-attention flagging

Entries whose Category or Payment Method points at a deleted label — because the label they were
using got deleted, and deletion cascades (see above) — show a warning-colored icon and subtitle
text in the list. This flag isn't a stored setting; it's computed on the fly from whether the entry
currently points at "No Category" / "No Payment Method". Recategorize the entry (open it, pick a
real category or payment method, save) and the flag clears itself immediately — there's nothing to
manually acknowledge or dismiss.

There's no separate "needs attention" screen. The **Needs attention** chip in History is the
entire feature: it's the same list, filtered.

---

## Analytics: how am I trending

**Analytics** is the third tab. Where History answers "what did I buy", Analytics answers "how am
I trending" — same underlying entries, different question, so it's a separate view rather than a
mode of the list.

At the top are the controls:

- **Date range** — same control as History, defaulting to the **last 30 days**.
- **Category** — pick any single category at any level, or leave it on **Combined** for all of
  them. The **✕** next to a chosen category returns you to Combined.
- **Day / Week / Month** — the time buckets the line chart groups spending into.

Below them, top to bottom:

1. **Total spending** for exactly the scope and range you selected.
2. **Spending over time** — a line chart of per-period totals.
3. **By category** — a bar breakdown, **Combined scope only**.
4. **Transactions** — the same list from History, matching the same scope, tappable to edit.

Every one of those four is driven by the same filter, so they can't disagree with each other. The
total is always the sum of the list beneath it.

### Category rollup

Selecting a parent category includes **everything nested under it**, automatically. Choose "Food"
and the total covers Food, Food > Restaurants, and Food > Restaurants > Fast Food together.

This is also why moving a label changes Analytics but not your entries: the entry still points at
the same label, but that label now rolls up under a different parent. The move confirmation warns
about exactly this.

### Day, Week, or Month

The line plots **what you spent in each period**, not a running total that only ever climbs. A flat
line means steady spending, not zero spending.

The app picks a sensible default: **Week**, dropping to **Day** when your range is under 14 days so
the chart isn't a single lonely point. **Once you tap a bucket yourself, your choice sticks** and
the app stops second-guessing it, even if you later change the date range.

A week is always 7 calendar days starting Monday. Periods with no spending are plotted as zero
rather than skipped, so a quiet stretch reads as a genuine gap instead of a straight line drawn
over it.

### Why "By category" sometimes isn't there

The bar breakdown appears **only for Combined scope**. Once you've narrowed to a single category,
there's nothing left to break down — the total and the chart are already about that one category,
so a breakdown would just restate it.

If you have a lot of categories, the chart shows the largest and folds the rest into a single
**"Other"** row, so a long tail of tiny bars doesn't drown out what actually matters. The full
detail is always in the transaction list below.

### Why the Analytics list stops at 50

The transaction list at the bottom of Analytics shows at most the **50 most recent** matching
entries. When there are more, a line beneath it says so and points you to History.

This trims **only that list**. The total, the line chart, the bar breakdown, and CSV export all
still cover every matching entry — so the headline figure never disagrees with the number of rows
you can see, it just summarizes more of them than are listed. History is the place to browse the
full set; it scrolls through any number of entries.

### What Analytics counts

Only what your filters let through. Deleted entries are excluded. Entries sitting in
"No Category" still count toward the **Combined** total — they're real spending, just unfiled — and
show up as their own "No Category" bar, which is often the nudge to go re-file them.

An empty range shows a **$0.00** total and an empty chart rather than silently widening the range
to find something to display.

---

## Confirmations

Every action that creates, renames, moves, or deletes a **label** asks first, and tells you the
consequences in real numbers — how many entries a rename touches, how many sub-items a delete takes
with it, how many entries will fall back to "No Category". Deleting a **transaction** also asks
first, with a plain "Delete this transaction?" prompt. Bulk-reassigning entries in History asks
too, stating how many entries will be affected.

Logging or editing a transaction's fields is deliberately **not** behind a confirmation. Day-to-day
entry is meant to be fast; only irreversible or structural changes are worth an extra tap.

---

## Your data

Everything is stored locally on your device. There's no account and nothing is uploaded.

**This also means there's no backup.** If you lose the device or uninstall the app, the data is
gone. **CSV export** (below) is your manual safety net — there's no automatic one.

### Making a backup

Export to CSV periodically and keep the file somewhere that isn't the device — email it to
yourself, drop it in cloud storage, whatever you'll actually do. A habit of exporting after any
significant stretch of logging is the whole safety net.

Two things worth knowing:

- **Export honours the current filters**, so to capture *everything* you must first widen the date
  range and clear the category, payment method, and search filters. Exporting from a narrowed view
  backs up only that slice — quietly, since a small file looks like a successful export.
- **There's no import.** CSV is a readable record, not a restore button; recovering from it means
  re-entering the data. It guarantees your history survives, not that the app can rebuild itself.

On **Windows** there's a stronger option: the entire database is one file at
`Documents\spending_tracker.sqlite`. Copy it while the app is closed and you have a complete
snapshot that can be restored by putting it back. On Android and iOS that file lives in private
app storage you can't reach, so CSV export is the practical answer there.

---

## Exporting to CSV

Both **History** and **Analytics** have an export icon (the share icon) in the top app bar. It
exports **exactly what that view is currently showing** — whatever filters are active there, and
nothing else.

There's no separate export screen and no export-specific filter to configure: History and
Analytics each keep their own independent filters (narrowing one never affects the other), and
tapping export just serializes whatever the tapped view is filtered to at that moment. Export from
a "this month, Food category" History view and you get exactly that set — not your full history.

Each row is one transaction: date, amount (as a plain decimal, e.g. `12.34`), Category, Payment
Method, Note, and Additional notes. If nothing matches the active filters, you still get a file —
just the header row and no data, never a silent fallback to exporting everything.

- **On phone (iOS/Android)**, export hands the file to your device's **share sheet** — save it,
  send it, or open it in whatever app you choose. There's no in-app file path, since iOS in
  particular has no user-visible filesystem to save into directly.
- **On desktop (Windows)**, export opens a **save dialog** so you pick exactly where the file goes.

If the export can't complete for some reason, you'll see a brief message rather than a silent
failure or a crash.

---

## Platform support

| Platform | State |
| --- | --- |
| **Android** | Works. |
| **Windows** | Works. Export opens a save dialog, and the database file is reachable for backups (above). |
| **iOS** | Built to run there — nothing in the app is Android- or Windows-specific — but it has **not been tested on an actual iOS device yet**, because that needs a Mac. Expect it to work; don't assume it until someone has run it. |

## Not built yet

Every feature described in this guide is built and working. There is no missing functionality at
this point — the remaining work is verifying the app on a real iOS device.

### Known limitations (by design)

Deliberately out of scope, not oversights:

- Single user, single device — no sharing, no sync between devices
- One currency
- Expenses only — no income or refunds
- No edit history on entries
- No duplicate detection — logging the same purchase twice is on you to notice
- No bank connection; all entry is manual
- No manual reordering of labels (alphabetical only)
- No CSV import — export is a record, not a restore path
- Analytics lists at most 50 entries (totals and charts still cover all of them)
