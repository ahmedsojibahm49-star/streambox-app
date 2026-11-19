# Fix 4 — Full senior audit (2026-11-19 ~17:00)

Senior QA audit + fix pass over the whole StreamBox Flutter app, after
Fix 1 (direct Hive paths), Fix 2 (resilient credential storage) and
Fix 3 (developer photo). All changes are in place in this project.

## Verification

- `flutter analyze` → **No issues found!**
- `flutter test` → **125/125 pass** (117 baseline + 8 new in
  `test/audit_fixes_test.dart`)
- No new dependencies. No i18n keys added/changed. No features removed.
- Untouched as instructed: keystore, keystore-passwords.txt,
  `.github/workflows/build-apk.yml`, the release-signing block in
  `build.gradle.kts`.

## Blockers fixed

1. **AndroidManifest had NO INTERNET permission** — every network call
   (provider fetch, images, video, YouTube) would fail on Android.
   Added `<uses-permission android:name="android.permission.INTERNET" />`.
2. **Sign-up was not atomic** (`lib/services/auth_service.dart`) — the
   profile was written BEFORE the credential hashes, so a credential
   failure left an account that could neither be logged into nor
   re-created. Credentials are now written first, profile last.
3. **Backup restore was not atomic** (`lib/services/backup_service.dart`)
   — `restoreData` cleared all boxes first, then parsed entries; one
   corrupt entry threw midway and wiped all local data. Everything is
   now parsed BEFORE any box is cleared.
4. **Parser dropped `youtubeId`** (`lib/services/provider_service.dart`)
   — `_parseEpisodes` rebuilt episode maps without the field, so YouTube
   playback was unreachable for every repo despite player support.
   Validated + preserved; documented in `docs/provider-format.md`.

## Major fixes

5. **Repo fetch downloaded the whole body before the 5 MB check** — a
   huge file could OOM the app. Now streamed with an incremental cap
   (aborts mid-download) + a body-read timeout + generic catch.
6. **Backup export fallback was unguarded** — it called
   `getApplicationDocumentsDirectory()` (broken path_provider on the
   user's device) and `SharePlus.share` with no guard. Now uses the new
   `bestWritableAppDir()` (direct Android paths first, no platform
   channel), guards the share sheet, and throws `BackupException` on
   failure. New helper in `lib/services/storage.dart`.
7. **Player platform calls unguarded** (`lib/screens/player/player_screen.dart`):
   post-init `seekTo`/`setPlaybackSpeed`/`play`, play/pause/seek/speed,
   fullscreen/orientation `SystemChrome` calls, `launchUrl`, controller
   dispose/close, and the unawaited `_loadEpisode` entry point — all
   wrapped; failed controllers are disposed; `_openInBrowser` checks
   the launch result and shows a snackbar on failure.
8. **Details share button** fired `SharePlus.share` unawaited and
   unguarded — now awaited with try/catch + snackbar.
9. **Backup import `FilePicker.pickFile` was outside the try block** —
   a platform-channel throw was an unhandled async error. Now inside.
10. **Search deep links applied only once** — the `_initialized` flag
    ignored later deep links (Home "See all" for Movies did nothing
    after Anime). Params are now re-applied whenever the query string
    changes; added `?genre=` support.
11. **Details genre chips were dead buttons** (`onTap: () {}`) — they
    now open Search filtered to that genre.

## Minor fixes

12. `Clipboard.setData` unguarded in `code_popup.dart` and
    `startup_error_screen.dart` — wrapped (the error screen exists
    precisely for broken-platform devices).
13. `HistoryNotifier.record` could throw into unawaited callers
    (player/reader progress timers) — now best-effort, never throws.
14. Reader `CachedNetworkImage.evictFromCache` unawaited/unguarded —
    now a guarded `_evictPage` helper with bounds checks.
15. Providers/AddRepo screens caught only `RepoException` — added
    generic catches showing `common.errorGeneric` (messages captured
    before awaits to keep `use_build_context_synchronously` clean).
16. `_seedAndRefresh` in `catalog_providers.dart` caught only
    `RepoException` — added generic catch (runs unawaited from build).
17. Settings theme/locale/notification setters unguarded (called
    unawaited from onTap) — Hive failures now show a snackbar and keep
    the old value.
18. Details/Library list toggles + history clear/remove unguarded —
    wrapped with snackbar feedback.
19. **Delete account had a service method + i18n strings but NO UI** —
    added a Profile row with confirmation dialog (existing keys
    `auth.deleteAccount` / `auth.deleteAccountConfirm` /
    `auth.accountDeleted`); router redirect sends the user to /welcome.
20. Details action buttons + Search/Manga sort buttons were bare
    `GestureDetector`s — now `FocusableCard` so D-pad on Android TV can
    reach them.
21. Stale Home comment ("providers stub throws until the providers
    workstream lands") corrected.

## Android / iOS / TV audit (inspection)

- `MainActivity.kt`: correct package `com.kizoo.streambox`, plain
  `FlutterActivity`. OK.
- `AndroidManifest.xml`: Leanback feature + `LEANBACK_LAUNCHER` +
  `android:banner="@drawable/tv_banner"` intact; `tv_banner.png`
  present. `extractNativeLibs` absent (= default true). OK after the
  INTERNET fix. No other permissions (none needed).
- `build.gradle.kts`: minSdk/targetSdk from Flutter; no
  minify/R8 (stays OFF); release-signing block intact, untouched.
- `gradle.properties` / `settings.gradle.kts`: standard Flutter
  template values, nothing broken. AGP 9.3.1 / Kotlin 2.4.20 as
  scaffolded.
- iOS: `Info.plist` basics intact, bundle id `com.kizoo.streambox`,
  portrait + landscape orientations. Inspection only — no macOS here.
- Workflow (read-only check): keystore decode + `key.properties`
  generation look correct (`storeFile=../streambox-release.keystore`
  resolves relative to `android/app`); nothing to change.

## Known limits / NOT fixed

- **ResilientCredentialStorage hang**: deliberately NOT changed (per
  brief — documented known limit). A HANGING secure-storage call is not
  rescued; startup is protected by the splash 8s timeout, but a hang
  during login would freeze the login button. User-side check: if login
  ever hangs >10s, force-stop the app and retry; report it if it
  recurs.
- **No device test possible in this VM.** The INTERNET-permission fix,
  YouTube playback, direct video, share sheet, file picker, TV D-pad
  and the backup export fallback all need confirmation on his phone/TV.
- iOS/TV untested (inspection only).
- Notifications toggle is in-app only (no push in this build) — as
  designed; the Settings copy says so.

## New tests (8, in test/audit_fixes_test.dart)

- Sign-up atomicity: failing 2nd credential write → no profile left,
  retry succeeds and login works.
- Restore atomicity: corrupt library entry → throws `invalidFile`,
  existing profile + library intact; valid payload still restores.
- `youtubeId` preserved through parsing (incl. both-sources episode);
  non-string `youtubeId` rejected with a specific error.
- Streamed fetch: 20×1 MB chunked body aborts after 6 chunks (5 MB
  cap) with "too large".
- `bestWritableAppDir`: uses direct candidates first; skips an
  unwritable candidate.
