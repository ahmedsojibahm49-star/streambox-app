# StreamBox v1.0.4 — fix pass record (2026-11-19)

v1.0.3 was confirmed working on the device (app opens, login works,
Profile/Developer/player/Details render). v1.0.4 fixes the six issues
the user reported from his v1.0.3 screenshots, plus five real bugs found
during verification. Version bumped to 1.0.4+4 (pubspec + in-app
"Version 1.0.4" string); installs over release-signed v1.0.3, no
uninstall needed.

## The six requested fixes

### 1. Developer is a full page, not a dialog
- New route `/developer` (`lib/screens/developer_screen.dart`):
  gradient-ring photo, "Jarif Ahmed", role, version pill, bio.
- Profile → Developer and Settings → Developer now navigate to it;
  both duplicated `_showDeveloper` dialog methods deleted.
- New i18n keys `developer.role` / `developer.bio` (en + bn).

### 2. Player polish
- **Pause "00" — root cause:** the episode-row circle rendered the
  Iconsax Bold pause glyph at 18px; two fat rounded bars read as "00".
  Fix: new `lib/widgets/pause_bars.dart` — `PauseBars` draws two tall
  narrow rounded rectangles (width 0.28×height, one-bar gap), used only
  when the episode is current AND actually playing.
- **0:00 / 0:00 with "Now playing" — three compounding causes:**
  (a) `_loadYoutube` cleared the spinner synchronously before the
  WebView started loading (the 2s grace delay was dead code);
  (b) no failure path if the YouTube WebView never emitted a value —
  silent black screen forever; (c) the episode row showed "Now
  playing" unconditionally. Fixes: spinner clears only on the first
  real player state or error; 8s grace timer → visible error state
  with Retry; `_loadDirect` initialize 20s / play 10s timeouts;
  controls hidden while initializing; "Now playing" gated on
  actually playing; tapping the current episode toggles play/pause.
- Error overlay fits the ~202px portrait video area (compact mode +
  scroll); up-next card scrolls too.

### 3. Details page — "Resume" + no clipping + Figma polish
- Button now says just **"Resume"** (new key `details.resume`,
  en + bn). Never-started items still "Watch now" / "Read now".
- **Clipping — root cause:** the CTA label had no flex/ellipsis
  protection, so "Resume episode…" overflowed into the bookmark
  button at 360px. Fixes: action row is a `LayoutBuilder` (icon
  buttons shrink to 44px under 400px content width);
  `GradientButton` label wrapped in `Flexible` + ellipsis (also
  protects Bangla labels and large font scales); resume caption
  ("Episode 3 · 12:34") under the button; resume target row
  highlighted with saved position; title capped at 3 lines.

### 4. Provider JSON — multi-catalog support + robust add flow
- **"No plugin appeared" — three root causes (his file was never
  seen):** (a) multi-catalog files were rejected outright (parser
  only accepted one `{"name","items"}` object); (b) a UTF-8 BOM
  kills `jsonDecode` (Windows Notepad saves UTF-8 WITH a BOM by
  default); (c) the error was invisible — red box below the
  14-line JSON field, below the fold, no scroll.
- `parseRepoDocuments` accepts (i) single-catalog object,
  (ii) `{"providers": [...]}`, (iii) top-level array of catalogs.
  Each catalog becomes its own repo row (own id/name/items,
  enable/disable/delete individually). Per-catalog errors name the
  catalog (`Provider #2 is missing a "name"...`). Max 50
  providers/file. BOM-tolerant. Stable ids (single-catalog keeps
  the exact v1.0.3 id; later catalogs get `-2`, `-3`…).
  Extension-index files (apk/pkg markers) are rejected with a clear
  message — JSON catalogs only, per the standing boundary.
- Refresh re-syncs siblings from the same source URL; stale
  siblings are removed with their items.
- Add Repo screen: success names all added providers; exact error
  message shown and scrolled into view; stale-error-across-tabs
  and double-submit fixed.
- Providers screen: delete-during-refresh resurrection and
  toggle race fixed.
- `docs/provider-format.md` documents the multi-catalog format.

### 5. Search icon invisible — NOT a colour bug
- Verified three ways (font-file analysis, FreeType render, his
  v1.0.3 screenshot): the colour binding was already correct.
  The defect is the glyph: **`Iconsax.search_normal` (U+EF20) is
  malformed in iconsax_flutter 1.0.1** — its two ring contours
  have the same winding direction, so it renders as a solid disc
  + dot, not a magnifier. `Iconsax.search_normal_copy` (U+EF23) is
  the glyph that renders as a magnifier outline. General finding:
  in iconsax_flutter 1.0.1, base names are Bold (filled) and
  `_copy` names are Linear (outline) — the opposite of the
  pubspec comment.
- Home switched to `search_normal_copy` + tooltip; header added to
  the Home empty state (it was missing entirely when the catalog
  was empty). Same swap in bottom nav, search field, Search
  screen, Manga screen.

### 6. Settings audit
- Settings/Backup: stale notifications switch (now a
  ValueListenableBuilder on the settings box); mistyped backup
  code killed the flow (inline validation, dialog stays open);
  backup export/import wrong-code loops re-ask instead of
  dropping out; non-UTF-8 backup file gets a proper error;
  stacked snackbars routed through the shared helper.
- Providers/AddRepo: see Fix 4.

## Bugs found during verification (all fixed)
- **video_player 2.14 `dispose()` hangs forever after a failed
  `initialize()`** (dispose awaits an internal completer that only
  completes when create returns). Player now disposes with a 2s
  timeout (`_disposeVideoController`); without this the error
  state could never appear on a broken-plugin device.
- **Player saved progress from `dispose()` via `ref.read`** —
  Riverpod throws on a disposed ref, aborting the rest of dispose
  and leaving the progress timer pending. The notifier is now
  cached in initState.
- **`HistoryNotifier.record` / `clear` / `remove` and the library
  toggles set state after an async gap without a mounted check**
  — a provider disposed mid-write threw UnmountedRefException.
  All five now check `ref.mounted` first.
- **Details `_listRow` passed BOTH `borderRadius` and `shape` to
  `Material`** for highlighted rows — framework assertion, the row
  crashed before rendering. Now one or the other.
- **Backup code dialog disposed its TextEditingController in a
  `finally` after `showDialog` returned** — but the dialog widget
  stays mounted through the pop animation and rebuilds, touching
  the disposed controller. The dialog is now a StatefulWidget
  that owns the controller lifecycle.
- **Player seek-bar knob clipped** at 0% / overshot at 100% —
  clamped.
- **Details Material assertion + GradientButton overflow** — see
  Fix 3.

## Verification (all green, 2026-11-19)
- `flutter analyze`: 0 issues.
- `flutter test`: **163/163 pass** (125 baseline + 28 provider
  multi-catalog + 4 player/details + 6 UI).
- `flutter build web --release`: succeeds (build/ cleaned after).
- Fresh-copy check (pub get + analyze 0) in a ~/workspace dir.
- Workflow YAML parses (11 steps, release signing intact).
- Keystore + keystore-passwords.txt untouched; secrets sweep clean.

## Honest limits
- No device test in this VM (no Android SDK/device). The user must
  confirm on his phone: Developer page, pause icon, Resume button,
  search icon, provider add with HIS json file (never seen — if it
  still fails he should send the file), Settings flows.
- iOS build, Android TV behavior, Bangla string wrapping:
  untested on device, as before.
- A hanging (not throwing) secure-storage call is still not
  rescued (v1.0.3 limit, unchanged).
