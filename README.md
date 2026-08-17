# Spending Tracker

A personal expense tracker built with Flutter. Single-user, offline-first, local SQLite —
no accounts, no server, no sync.

**Status:** Phases 0–8 complete — feature-complete for v1 on Android and Windows (scaffold, data
foundation, Categories & Payment Methods, transaction entry/edit/delete, History with filtering
and needs-attention flagging, bulk recategorization, Analytics with rollup totals and charts, CSV
export, and platform hardening), plus **CSV import** added afterwards. The remaining work is the
iOS pass, which needs Mac access — see [Platform status](#platform-status).

## Documentation

| Document | For |
| --- | --- |
| [User guide](docs/user-guide.md) | How to use the app, and what it does and doesn't allow |
| [Product spec](docs/spending-tracker-spec.md) | Locked requirements — read-only |
| [Implementation plan](docs/implementation-plan.md) | Data model, phase briefs, name inventory |
| [CLAUDE.md](CLAUDE.md) | Working agreements and conventions for contributors |

## Development

```
flutter run -d windows            # fastest inner loop
flutter run -d <android-device>
dart run build_runner build       # after touching data/tables.dart or data/database.dart
flutter analyze
flutter test
```

Schema changes have extra steps — see the "Schema migrations" section of
[CLAUDE.md](CLAUDE.md). The on-device database is the user's only copy, so migrations are
tested against real snapshots in `drift_schemas/`.

The suite includes a ~5k-row performance benchmark tagged `perf`. It is worth keeping in the
default run — it is what caught the DST bucketing hang — but it seeds thousands of rows per
test, so skip it for a fast inner loop:

```
flutter test --exclude-tags perf
```

## Platform status

| Platform | State |
| --- | --- |
| **Android** | Supported and exercised throughout the build. |
| **Windows** | Supported. Builds and runs; used as the primary development target. |
| **iOS** | Code is kept iOS-clean (no hardcoded paths, share-sheet handoff, all packages verified for iOS support), but **it has never been built or run** — this project has no Mac access. Treat first-run iOS as unverified until that pass happens. |

If `flutter build windows` fails with `error C1083: Cannot open source file` pointing at
`windows/flutter/ephemeral/`, that is stale scaffold state rather than a code defect:
`flutter clean && flutter pub get` regenerates the wrapper files.

## Backing up your data

There is no automatic backup, no server copy, and no account. **If the device is lost or the app
is uninstalled, the data is gone.** Two ways to keep a copy:

### 1. CSV export (the everyday safety net)

Tap the share icon in the top app bar from **History** or **Analytics**. The export contains
exactly what that view is currently filtered to — so to export *everything*, widen the date range
first and clear the category, payment-method, and search filters. On Windows you pick a save
location; on Android/iOS it goes through the share sheet.

CSV is readable anywhere (Excel, Sheets, any text editor) and is written as UTF-8, so accented
characters and emoji in notes survive intact.

**Import CSV** (overflow menu, ⋮) reads those files back, so an export is a real restore path.
Import previews before writing, commits atomically, and prompts per exact-duplicate row with
keep-both / replace / skip and an "apply to the rest" option. The one thing it cannot restore is
label **nesting** — the format stores a label's own name, not its path, so a restored
`Food > Restaurants` comes back as a top-level `Restaurants` and the tree is rebuilt with **Move**
on the manage screen.

### 2. Copying the database file (a true snapshot)

The full database is a single SQLite file named `spending_tracker.sqlite`, in the platform's
application-documents directory:

| Platform | Location |
| --- | --- |
| **Windows** | `%USERPROFILE%\Documents\spending_tracker.sqlite` |
| **Android** | App-private storage — not reachable without `adb` or a rooted device. Use CSV export instead. |
| **iOS** | App sandbox — not user-visible by design. Use CSV export instead. |

Copying that file while the app is **closed** captures everything, and dropping it back in the
same location restores everything. This is the only true restore path, but it is realistically
only available on desktop; on mobile, CSV export is the practical answer.
