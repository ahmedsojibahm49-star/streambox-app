# v1.0.5 — Icon polish pass (Linear icons only, no row chevrons)

Version `1.0.5+5`. Built on v1.0.4 + notification bell. Installs over the
release-signed v1.0.4; tag `v1.0.5` for the GitHub Release.

## What the user asked for (Nov 20)

1. **No Bold (filled) icons anywhere** — every icon in the app must be
   Linear (outline) style.
2. **No unnecessary small icons** — e.g. the small entry/chevron icon on
   Settings rows (Developer etc.). Remove decorative trailing chevrons.

## 1. Bold → Linear: every icon in lib/

In iconsax_flutter 1.0.1, BASE names are Bold (filled) and `_copy` names
are Linear (outline) — the opposite of the pubspec comment. Verified
again for this pass by rendering the actual TTF glyphs: across 10 sampled
pairs the base glyph carries 1.9–2.9× the ink of its `_copy` twin, and a
visual render of the ambiguous cases (link, share, translate, refresh,
sun, global, 10-second skip) confirmed every `_copy` is the outline
glyph. All 56 base names used in lib/ had a `_copy` variant except one:

- `refresh_2` (providers screen, last-refresh label) has NO `_copy`
  variant in the package — replaced by `refresh_copy`, the Linear
  circular arrow. The old glyph was a filled rounded square.

**116 replacements across 27 files** — every `Iconsax.<base>` became
`Iconsax.<base>_copy`. Highlights:

- **Bottom nav** (`bottom_nav_bar.dart`): the old code had it backwards
  — inactive tabs used Bold base glyphs and active tabs used Linear
  `_copy` glyphs (the doc comment even said so, wrongly). Now both
  states use the same Linear glyph; the active tab is shown by COLOUR
  (orange icon + label + gradient dot), never by glyph weight.
- **Details toggles**: My List / Favorite used to swap glyph weight by
  state (and inverted: in-list showed the outline). Now one Linear
  glyph in both states; the state is shown by the `active:` colour tint
  (orange icon + border + tinted background), which the button already
  had.
- **Player / reader**: back, 10-second skip, fullscreen, refresh,
  chapter arrows — all Linear now. The 10-second skip glyphs are
  identical in both variants (line art + "10"), so those swaps are
  visual no-ops. Play stays `play_copy` (Linear triangle in the
  gradient circle); pause stays the drawn `PauseBars` widget — both
  were already correct and are untouched.
- **Auth fields, dialogs, empty/error states, search, manga, library,
  backup, providers, settings pills, rating badge, app image
  placeholder** — all swapped the same way.
- **Notification bell**: kept (`notification_copy` on Home, and the
  Settings notifications row now uses `notification_copy` too — it was
  the last filled bell in the app).

After the pass, **zero Bold identifiers remain in lib/** — verified by a
glyph-aware scan (see Tests) and by rendering: all 57 distinct Iconsax
identifiers in lib/ end in `_copy`. No Material/Cupertino icons exist in
the app; there are no custom-drawn icons except `PauseBars`.

## 2. Chevron removal

- `settings_screen.dart` `_row` and `profile_screen.dart` `_row`:
  removed the trailing `arrow_right_1` chevron (+ its 8px spacer).
  Affects: Settings → Providers, Backup, About, Developer; Profile →
  Settings, Backup, Providers, About, Developer, Sign out, Delete
  account. Rows are still tappable (InkWell + card + label); the
  leading icons (which carry meaning) are kept.
- Kept on purpose: the Details episode/chapter row trailing icons
  (`play_circle_copy` / `book_copy`) — they are play/read affordances,
  not decoration; the reader's prev/next chapter arrows and the
  onboarding Next arrow — functional navigation, not decoration.

## 3. Version

- `pubspec.yaml`: `1.0.4+4` → `1.0.5+5`.
- The in-app version is a HARDCODED i18n string, not package_info_plus:
  `settings.aboutVersion` → `'Version 1.0.5'` (en) / `'সংস্করণ ১.০.৫'`
  (bn). Shown on the Developer page and in the About dialog.

## 4. Comments corrected

- `bottom_nav_bar.dart` doc comment (claimed active = Bold `_copy` —
  backwards), `pause_bars.dart` comment (called `pause_copy` Bold —
  it is Linear), `home_screen.dart` search/bell comments (the bell note
  said Settings used the filled bell — no longer true; the search note
  no longer spells out the banned identifier).

## Tests (7 new, 170/170 total)

`test/v105_icon_polish_test.dart`:

1. **Source scan**: reads every `lib/**/*.dart`, strips comments, fails
   if any of the 56 banned Bold identifiers appears (whole-identifier
   regex — `Iconsax.book` does not match `Iconsax.book_1` /
   `Iconsax.book_copy`).
2. **Version parity**: the `aboutVersion` string must match pubspec.
3. **Settings rows**: no chevron glyph of either style; rows still
   present and Developer still navigates.
4. **Profile rows**: same.
5. **Home bell (dark + light)**: `notification_copy` present, one
   widget, high-contrast colour in both themes.
6. **Bottom nav**: all five Linear glyphs render; no Bold twin renders;
   active tab is brand orange, inactive is muted.
7. Plus a rendered-screen sweep on Home/Settings/Profile: every `Icon`
   widget's `IconData` is checked against the banned set.

## Verification

- `flutter analyze` → 0 issues.
- `flutter test` → 170/170 pass (163 baseline + 7 new).
- `flutter build web --release` → succeeds; `build/` cleaned after.
- Fresh-copy check (pub get + analyze 0) → pass; copy deleted.
- Workflow YAML parses.
- ZIP: `streambox-flutter-v105.zip` (keystore + passwords + developer
  photo included; secrets sweep clean).

## Notes / honest limits

- No device test — the user must confirm on his phone: every icon reads
  as a clean outline in both themes, rows look right without chevrons,
  the bell is still there, the bottom nav active tab is orange.
- `android/local.properties` is NOT in this ZIP (it was in the v1.0.4
  ZIP by oversight — it carries the build machine's `flutter.sdk`
  path). `flutter pub get` regenerates it; nothing breaks.
- The Linear glyphs are thinner than the filled ones by design — at very
  small sizes (11px rating star) they are still legible, but that is
  worth a glance on a real phone.
