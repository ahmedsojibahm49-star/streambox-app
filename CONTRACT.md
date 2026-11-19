# StreamBox — Workstream Contract

Foundation built by the SETUP agent (2026-11-19). Every workstream builds on
this file's decisions. **Do not change the contracts below without telling the
coordinator** — routes, typeIds, box names, provider names and i18n keys are
shared surface.

- Flutter 3.50.0 (stable) / Dart 3.14.0, SDK at `~/flutter`
- Package: `com.kizoo.streambox`, app name **StreamBox**, version 0.1.0+1
- Platforms: Android, iOS, Web (TV via Android Leanback)
- Foundation state: `flutter analyze` 0 issues, `flutter test` 13/13 pass,
  `flutter build web --release` succeeds.

## 1. Decisions (locked)

| Area | Decision |
|---|---|
| State | **flutter_riverpod 3.5.0**, modern `Notifier`/`NotifierProvider` API only. `StateProvider` was REMOVED in Riverpod 3 — do not use it (and do not import `legacy.dart`). |
| Navigation | **go_router 18.1.4**, `StatefulShellRoute.indexedStack` for the 5 bottom-nav branches. |
| Storage | **Hive 2.2.3** boxes (all data local, no server). Credentials (password hash, device code) go in **flutter_secure_storage 11.2.0**, NEVER in a Hive box. |
| Material | Flutter 3.50 deprecates `package:flutter/material.dart` — import **`package:material_ui/material_ui.dart`** instead (the Material library was extracted to the `material_ui` package). Same for `GlobalMaterialLocalizations` (comes from material_ui). `flutter_localizations` is kept only for `GlobalWidgetsLocalizations`. |
| Icons | **iconsax_flutter 1.0.1** (`Iconsax.home`, …). The `iconsax` package (0.0.8, 2021) is Dart-2-only and cannot be used. Convention: base name = Linear (inactive), `_copy` suffix = Bold (active) — matches the Figma Linear-inactive / Bold-active rule. 2,012 icons. Never hand-drawn glyphs, never Material icons for brand UI. |
| Fonts | Bundled TTFs, NO runtime downloads. **Inter** variable font (`Inter-Variable.ttf`, weights 400/500/600/700 via the wght axis) + **HindSiliguri** (Regular/Medium/SemiBold/Bold) as the Bangla fallback (`fontFamilyFallback`). Source: google/fonts GitHub repo. |
| i18n | Hand-rolled maps (`lib/i18n/en.dart` + `bn.dart`), `tr(context, key)`. `intl` is used ONLY for locale-aware dates. |
| Backup crypto | `encrypt` 5.0.3 + `crypto` 3.0.8. Backup file is AES-encrypted, key derived from the device code. |
| Codegen | `hive_generator` 2.0.1 + **`build_runner` PINNED to 2.4.13**. Do NOT upgrade: build_runner ≥2.4.14 pulls analyzer ^6.5+ which needs the `_macros` SDK package that Dart 3.14 no longer ships (pub resolution fails). If the pin ever blocks you, hand-write the TypeAdapters instead of fighting the resolver. Generated `*.g.dart` files ARE committed. |
| Orientation | Manifest does NOT lock orientation. The player handles landscape itself. |
| Immersive | Android only, set once in main(): `SystemUiMode.immersiveSticky`. iOS/web untouched. |

## 2. File ownership

| Workstream | Owns (creates/edits) | Must NOT touch |
|---|---|---|
| **auth** | `lib/screens/splash_screen.dart`, `onboarding_screen.dart`, `welcome_screen.dart`, `signup_screen.dart`, `login_screen.dart`, `lib/services/auth_service.dart` (real impl), `authStateProvider` logic, backup export/import, `lib/screens/backup_screen.dart` | Router paths, theme tokens, models |
| **providers-data** | `lib/services/provider_service.dart` (real impl), `lib/data/sample_provider.dart`, `lib/providers/catalog_providers.dart`, `lib/screens/settings/providers_screen.dart` + `add_repo_screen.dart`, `assets/sample-repo.json` (+ root copy `sample-repo.json`), `docs/provider-format.md`, `tool/generate_sample_repo.dart`, `test/provider_test.dart` | Models' typeIds/fields (add fields only with a new HiveField number — never reuse), auth |
| **screens** | `lib/screens/home_screen.dart`, `search_screen.dart`, `manga_screen.dart`, `library_screen.dart`, `profile_screen.dart`, `settings_screen.dart`, `details_screen.dart`, `lib/widgets/*` (additive only) | Router paths, `BottomNavBar` tab order, theme tokens |
| **player-reader** | `lib/screens/player_screen.dart`, `reader_screen.dart`, video/reader controllers | Router paths, models |
| **verification** | `README.md`, integration tests, QA fixes anywhere (small, with a note in the ledger) | — |

Shared files — edit only with coordinator approval: `lib/main.dart`,
`lib/router/app_router.dart`, `lib/theme/app_theme.dart`, `lib/models/*`,
`lib/i18n/*` (except ADDING keys per §5), `lib/services/storage.dart`,
`lib/services/library_service.dart`, `pubspec.yaml`, this contract.

**Replacing a placeholder:** each route in `app_router.dart` returns a
`PlaceholderScreen`. Replace the builder with the real screen, keep the path
and parameter names. Delete `lib/screens/placeholder_screen.dart` when the
last placeholder is gone.

## 3. Hive typeId map (NEVER reuse or renumber)

| typeId | Class | File | Box |
|---|---|---|---|
| 0 | `ProviderItem` | `lib/models/provider_item.dart` | `catalog` |
| 1 | `ProviderRepo` | `lib/models/provider_repo.dart` | `providers` |
| 2 | `LibraryEntry` | `lib/models/library_entry.dart` | `library` |
| 3 | `HistoryEntry` | `lib/models/history_entry.dart` | `history` |
| 4 | `UserProfile` | `lib/models/user_profile.dart` | `profile` |
| 5 | `AppSettings` | `lib/models/app_settings.dart` | `settings` |
| 6 | `ContentType` (enum) | `lib/models/provider_item.dart` | — (embedded) |
| 7 | `LibraryList` (enum) | `lib/models/library_entry.dart` | — (embedded) |

Box names live in `BoxNames` (`lib/services/storage.dart`) — use the
constants, never string literals. Box keys:

- `catalog`: `"$providerId::$id"` (`ProviderItem.boxKey`)
- `providers`: repo `id`
- `library`: `"${list.name}::$providerId::$itemId"` (`LibraryEntry.boxKey`)
- `history`: `"$providerId::$itemId"` (`HistoryEntry.boxKey`)
- `profile`: single key `current`
- `settings`: single key `current`

**Adding a field:** append a new `@HiveField(n)` with the next free number,
run `dart run build_runner build --delete-conflicting-outputs`, commit the
regenerated `*.g.dart`. Never renumber existing fields.

**Episodes/chapters** are JSON-encoded strings on `ProviderItem`
(`episodesJson` / `chaptersJson`); use the `.episodes` / `.chapters` getters
which decode to `List<Map<String, dynamic>>`. Episode map:
`{number, title, videoUrl, durationSeconds}`. Chapter map:
`{number, title, pageUrls}`.

## 4. Route table

| Path | Screen | Owner |
|---|---|---|
| `/` | Splash | auth |
| `/onboarding` | Onboarding slides | auth |
| `/welcome` | Welcome (login / sign-up choice) | auth |
| `/signup` | Sign-up form | auth |
| `/login` | Login (email + password + device code) | auth |
| `/home` | Home feed (shell branch 0) | screens |
| `/search` | Advanced search (shell branch 1) | screens |
| `/manga` | Manga & manhwa (shell branch 2) | screens |
| `/library` | My List / favorites / history (shell branch 3) | screens |
| `/profile` | Profile + stats (shell branch 4) | screens |
| `/settings` | Settings | screens |
| `/settings/providers` | Providers (INSIDE Settings) | providers-data |
| `/settings/providers/add` | Add repo — via URL or pasted JSON | providers-data |
| `/details/:id` | Title details (`:id` = `"$providerId::$itemId"`) | screens |
| `/player/:id` | Video player | player-reader |
| `/reader/:id` | Manga/manhwa reader | player-reader |
| `/backup` | Backup & restore | auth |

**There is intentionally NO `/code` route.** The device-code popup is a
dialog: `showCodePopup(context, code: ..., onContinue: ...)` in
`lib/widgets/code_popup.dart`. Sign-up shows it, then routes to `/login`.

**Auth redirect (placeholder):** logged-out users are redirected to
`/welcome` for any route except `/`, `/onboarding`, `/welcome`, `/login`,
`/signup`; logged-in users are redirected from those auth routes to `/home`.
The auth workstream wires the real session check into `authStateProvider`
(keep the name and the `bool` state type).

## 5. i18n key-adding rule

- Add the key to **BOTH** `lib/i18n/en.dart` and `lib/i18n/bn.dart` in the
  same change, same spelling, same `{placeholder}` names.
- `test/i18n_test.dart` FAILS the build when the two maps drift (missing
  keys, extra keys, empty values, placeholder mismatch). 208 keys today.
- Group keys by feature (`home.*`, `search.*`, …). Use `tr(context, key)` in
  widgets, `trParams(context, key, {...})` for placeholders.
- Never hard-code user-visible strings in a screen — always a key.

## 6. Theme tokens

Use `AppColors`, `AppTheme` and `context.palette` — never hard-coded hex.

| Token | Dark | Light |
|---|---|---|
| bg | `#09090D` | `#F2F2F5` |
| surface | `#131318` | `#FFFFFF` |
| card | `#1C1C22` | `#FFFFFF` |
| border | white 8% | black 8% |
| text | `#F5F5F7` | `#111114` |
| muted | `#9C9CA6` | `#6E6E77` |

Brand (both themes): orange `#FF7700` → `#F03A02` gradient
(`AppColors.primaryGradient`), glow `BoxShadow` orange blur 24 alpha 0.45
(`AppColors.glowShadow`). Radii: 12 / 16 / 20 / 24. Font: Inter (+
HindSiliguri fallback). Text styles via `Theme.of(context).textTheme`.

**Settings pattern** (theme/locale): update the provider AND persist:
```dart
final box = Hive.box<AppSettings>(BoxNames.settings);
final settings = box.get('current') ?? AppSettings();
settings.themeMode = 'dark'; // or localeCode = 'bn'
await settings.save(); // or box.put('current', settings)
ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
```

## 7. Shared widgets (`lib/widgets/`, barrel `widgets.dart`)

GradientButton, GhostButton, AppTextField, SearchField, SectionHeader,
PosterCard, WideCard, ChipToggle, EmptyState, LoadingSkeleton (+ SkeletonBox),
ErrorState, FocusableCard (TV D-pad focus ring + Enter/Space activation),
RatingBadge, BottomNavBar (docked, 5 tabs — do not reorder), AppImage
(asset-or-network image with placeholder), showCodePopup dialog.

Poster/backdrop sources: pass an asset path (`assets/artwork/...`) or a
remote URL — `AppImage` handles both. Sample posters: the 15 bundled images
in `assets/artwork/` (see §9).

## 8. Services

- `AuthService` (`lib/services/auth_service.dart`) — interface + throwing
  stub. Auth workstream implements: signUp, login, logout, isLoggedIn,
  generateCode, verifyCode, exportBackup, importBackup.
- `ProviderService` (`lib/services/provider_service.dart`) — REAL impl
  (`HiveProviderService`, providers-data workstream, 2026-11-19).
  `fetchRepo` (http GET, 15s timeout, 5 MB cap, exact user-facing
  [RepoException] messages for network/timeout/non-200/invalid JSON),
  `parseRepoDocument` (pure, returns `ParsedRepo` = repo row + items;
  `parseRepo` kept for the original signature), `validateRepo`,
  `addRepoFromJson` (pasted JSON, `pasted://` source, not refreshable),
  `deleteRepo` (refuses built-in), `toggleRepo`, `listRepos`,
  `repoById`, `itemsForRepo`, `seedBuiltIn`, `refreshRepo`, `refreshAll`,
  `searchItems`, `itemsByType`. Caps: 1000 items/repo, 1000
  episodes/chapters/item. The built-in sample catalog (`sample`, 24
  fictional items, `lib/data/sample_provider.dart`) is seeded LAZILY on
  first read of `providersListProvider` — main.dart does not seed.
- `LibraryService` (`lib/services/library_service.dart`) — FULLY
  IMPLEMENTED. Providers: `myListProvider`, `favoritesProvider`,
  `historyProvider`, `continueWatchingProvider`,
  `isInMyListProvider` / `isFavoriteProvider` (family, key
  `(itemId, providerId)`). Screens use these, never the boxes directly.
- `DeviceCode` (`lib/utils/code_generator.dart`) — pure-Dart generator,
  `SB-XXXX-XXXX-XXXX`, alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`
  (no 0/O/1/I/L). Seeded with device id + crypto-random. Unit-tested.

## 9. Assets

- `assets/artwork/` — 15 cinematic images copied from
  `~/workspace/streambox/artwork/` (all 15 present): 9 posters, 4 wide
  backdrops, hero + player art for "Last Horizon". Fictional sample titles
  only (Last Horizon, Neon Frontier, Midnight City, Echoes of Tomorrow,
  Glass Detective, Northern Lights, Paper Moons, Silent Tide, Solar Winds,
  Wild Ember). Used for onboarding backgrounds, hero art, sample provider
  posters.
- `assets/fonts/` — Inter variable + Hind Siliguri ×4 (see §1).
- `assets/icon/icon.png` — launcher icon source (1024×1024 center-crop of
  the hero art; NOT hand-drawn). Generated via flutter_launcher_icons into
  Android mipmap + iOS AppIcon. `assets/icon/tv_banner.png` — 320×180 TV
  banner, also copied to `android/app/src/main/res/drawable/tv_banner.png`.

## 10. Android / iOS / TV

- Android: package `com.kizoo.streambox`, label `StreamBox`, Leanback
  launcher category alongside LAUNCHER, `android:banner="@drawable/tv_banner"`,
  `uses-feature android.software.leanback required=false`,
  `uses-feature android.hardware.touchscreen required=false`, orientation NOT
  locked. No Android SDK in this VM — APK builds run in GitHub Actions.
- iOS: bundle id `com.kizoo.streambox`, display name `StreamBox`. No iOS
  build verification is possible here — untested until a Mac/CI macOS runner.
- TV: D-pad navigation via `FocusableCard`; bottom nav + cards must all be
  focusable. Verification agent checks TV focus order.

## 11. Hard boundaries (non-negotiable)

- NO TMDB / Jikan / AniList / MovieBox / any piracy source or API.
- NO demo login. Auth is local sign-up → device code → login.
- NO real pirate provider names anywhere (code, sample data, UI strings).
- Providers are **JSON catalogs ONLY**: one JSON file per repo, fetched over
  HTTP(S), parsed into `ProviderItem`s. NO index.pb / protobuf, NO extension
  APKs, NO scraping, NO video-URL extraction. A repo URL must end in `.json`
  (enforced by `Validators.providerUrl`).
- Sample data is fictional only (the 10 titles in §9).
- All user data stays on-device. Backup = encrypted file unlocked by the
  device code; the code alone cannot fetch data on a new device without the
  backup file.

## 12. Build & verify

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd ~/workspace/streambox-flutter-app
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # after model changes
flutter analyze          # must be 0 issues
flutter test             # must pass
flutter build web --release   # smoke build (clean build/ after)
```

CI: `.github/workflows/build-apk.yml` — push to main / manual dispatch →
Java 17 → Flutter stable → pub get → analyze → test → `flutter build apk
--release` → uploads `streambox-apk` artifact. CI does NOT run build_runner
(see the workflow note).

## 13. Known gaps (for the verification agent to flag)

1. All 16 routes are placeholders — real screens are the workstreams' job.
   (Update 2026-11-19, auth: `/`, `/signup`, `/login`, `/backup` are now
   real screens. `/onboarding` and `/welcome` are still placeholders —
   screens workstream owns them per the coordinator's assignment.)
   (Update 2026-11-19, providers-data: `/settings/providers` and
   `/settings/providers/add` are now real screens.)
2. `AuthService` / `ProviderService` are throwing stubs.
   (Update 2026-11-19, auth: `AuthService` is fully implemented
   (`LocalAuthService`); `ProviderService` is still a stub.)
   (Update 2026-11-19, providers-data: `ProviderService` is now fully
   implemented (`HiveProviderService`) — no throwing stubs remain.)
3. `authStateProvider` is a stub boolean — the router redirects, but no real
   session exists yet.
   (Update 2026-11-19, auth: real. Splash refreshes it at startup;
   login/logout flip it. Session persists via a secure-storage flag.)
4. No iOS build verification (no Mac here); no Android build verification
   (no Android SDK here — first real APK comes from GitHub Actions).
5. Launcher icon is a center-cropped artwork photo, not a designed mark —
   acceptable for now; a proper logo is a design task, not setup.
6. `flutter pub outdated` reports 20 packages with newer versions blocked by
   constraints — mostly the build_runner 2.4.13 pin and its transitive deps.
   Expected; do not "fix" by upgrading build_runner.
7. Previous stopped attempt left staging at
   `~/workspace/.sb-staging-prev-attempt/` (14 partial Dart files + 15
   images) — preserved for reference, NOT part of this project.

## 14. Auth handoff notes (2026-11-19, auth workstream)

- **Auth flow (built):** Sign Up → code popup (shown once, "I saved my
  code" to continue) → Login (email + password + device code) → animated
  success → Home. Sign-up does NOT start a session; login does.
  `authServiceProvider` exposes `signUp` (returns `SignUpResult` with the
  code), `login`, `logout`, `deleteAccount`, `isLoggedIn`,
  `currentProfile`, `verifyCode`, `hasSeenOnboarding` /
  `markOnboardingSeen`, `exportBackup` / `importBackup`.
- **Screens workstream — please link these:**
  - Settings → **Backup & restore** row → `context.go('/backup')`
    (route exists, screen built; i18n key `settings.backup`).
  - Settings → **Sign out** row → `await authService.logout()` then
    `ref.read(authStateProvider.notifier).setLoggedIn(false)` (the router
    redirect sends the user to `/welcome`). Keys: `settings.signOut`,
    `settings.signOutConfirm`.
  - Settings → **Delete account** row → confirm dialog (keys
    `auth.deleteAccount`, `auth.deleteAccountConfirm`) →
    `await authService.deleteAccount()` then set logged-in false.
  - Onboarding slides (screens-owned): call
    `await authService.markOnboardingSeen()` when the user finishes or
    skips, so splash routes returning users to `/welcome`.
  - Profile screen: read the profile from
    `ref.read(authServiceProvider).currentProfile`.
- **Backup format:** `.sbbackup` JSON envelope
  `{version: 1, salt, iv, ciphertext}` — AES-256-CBC, key
  `SHA-256(code + salt)`. Payload carries profile, credential hashes,
  library, history, providers, cached catalog and settings. Import
  replaces all local data and clears the session (user logs in again).
  The UI states the honest limit: no server, so the code alone cannot
  fetch data on a new device — the backup file is the carrier.

## 15. Catalog providers (providers-data, 2026-11-19)

`lib/providers/catalog_providers.dart` — the read API screens and the
player/reader consume. Never touch the Hive boxes directly.

```dart
// All repos, built-in first. Notifier actions:
final providersListProvider =
    NotifierProvider<ProvidersListNotifier, List<ProviderRepo>>(...);
//   addFromUrl(String url) -> Future<ProviderRepo>
//   addFromJson(String rawJson) -> Future<ProviderRepo>
//   delete(String repoId) -> Future<void>        // throws for built-in
//   toggle(String repoId, bool enabled) -> Future<void>
//   refresh(String repoId) -> Future<void>
//   refreshAll() -> Future<void>

// Every item from every enabled repo, newest first.
final allEnabledItemsProvider = Provider<List<ProviderItem>>(...);

// Enabled items of one type, newest first.
final itemsByTypeProvider =
    Provider.family<List<ProviderItem>, ContentType>(...);

// One item by box key "$providerId::$itemId" (the :id in /details/:id),
// or by bare item id (searches ALL repos, enabled or not). Null on miss.
final itemByIdProvider = Provider.family<ProviderItem?, String>(...);
```

Repo JSON format: `docs/provider-format.md`. Sample repo JSON:
`assets/sample-repo.json` (bundled asset — registered in pubspec.yaml) and
`sample-repo.json` at the project root (for hosting). Both are GENERATED
from `lib/data/sample_provider.dart` via
`dart tool/generate_sample_repo.dart` — never edit by hand.

Service errors are [RepoException] (message is user-facing English shown
directly in the UI). New i18n keys: 19 `providers.*` keys added 2026-11-19
(`addRepo`, `addViaUrl`, `addViaJson`, `pasteJsonLabel`, `pasteJsonHint`,
`loadExample`, `exampleLoaded`, `refresh`, `removeConfirm`, `providerRemoved`,
`providerRefreshed`, `refreshFailed`, `noAddedRepos`, `noAddedReposBody`,
`neverFetched`, `cantDeleteBuiltIn`, `adding`, `refreshing`,
`invalidJson` — plus the 16 pre-existing keys).
