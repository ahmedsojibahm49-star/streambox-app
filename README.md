# StreamBox

**StreamBox** is a local-first Flutter app for watching anime and movies and
reading manga and manhwa — from **your own JSON provider catalogs**.

There is no server, no account database, no API key, and no built-in
streaming service. A provider is a single JSON file that lists titles and the
direct video/page links its author chose to include. You add a repo URL (or
paste JSON) in **Settings → Providers**, and StreamBox turns it into a
browsable catalog with search, library, history, a video player and a manga
reader.

- Package: `com.kizoo.streambox` · version 0.1.0+1
- Platforms: Android (phone + Android TV), iOS, Web
- Flutter 3.50.0 / Dart 3.14 · Riverpod 3.5 · go_router · Hive (local storage)
- Languages: English + Bangla (বাংলা) · Themes: Dark / Light / System

## Features

- **Home feed** — hero banner, continue-watching rail, trending and
  per-type rows, all from your enabled repos.
- **Advanced search** — text search with filters (type, genre, year, rating,
  status, provider), sort options and result counts, plus recent searches.
- **Manga & manhwa tab** — a dedicated bottom-nav tab for readable titles.
- **Library** — My List, Favorites, History and Continue Watching, with
  per-item remove and clear-history.
- **Details** — poster/backdrop hero, rating, genres, overview, episode and
  chapter lists, add to My List / Favorites.
- **Video player** — direct MP4-style URLs and YouTube links, resume from
  where you left off, playback speed, seek, fullscreen landscape.
- **Manga reader** — page-by-page and vertical-scroll modes, tap zones,
  chapter navigation, saved page, on-screen brightness control.
- **Providers (inside Settings)** — add repos by URL or pasted JSON, enable /
  disable, refresh, remove; the built-in Sample Catalog (24 fictional titles)
  can be turned off but not deleted.
- **Code login** — local sign-up, a per-device code, login with
  email + password + code. See below.
- **Backup & restore** — export everything to an encrypted `.sbbackup` file,
  import it on another device with the same code.
- **Settings** — theme, language (English / Bangla), providers, backup,
  notifications toggle, About, Developer.
- **Android TV** — Leanback launcher, TV banner, D-pad focus on cards and nav.
- **Android immersive mode** — the system navigation bar hides on entry
  (swipe brings it back).

## The code-login system (how it really works)

There is **no server and no online account**. Everything lives on the device:

1. **Sign up** with an email and password. The app generates a per-device
   code like `SB-XXXX-XXXX-XXXX` and shows it **once** in a popup. Write it
   down — the app never shows it again.
2. **Log in** with email + password + that code.
3. The password hash and the code hash are stored in the platform secure
   storage (`flutter_secure_storage`); your profile, library, history,
   providers and settings live in local Hive boxes. Nothing is ever sent
   anywhere.

**The honest limit:** the code alone cannot fetch your data on a new device,
because there is no server holding it. The **encrypted `.sbbackup` file is
the carrier** — export it from Settings → Backup & restore, keep the file
somewhere safe, and import it on the new device with the same code. Without
the backup file, a new device starts empty even with the correct code. If
you lose the code, you cannot log in again and cannot open your backups.

## Provider JSON format

A provider repo is **one JSON file** per catalog, fetched over HTTP(S) and
parsed into titles. StreamBox never scrapes pages, extracts video URLs, or
loads extensions — the repo author supplies direct links, and the app plays
or displays exactly those links.

The full spec lives in [`docs/provider-format.md`](docs/provider-format.md).
The short version:

```json
{
  "name": "My Catalog",
  "version": 1,
  "items": [
    {
      "id": "last-horizon",
      "type": "anime",
      "title": "Last Horizon",
      "posterUrl": "https://example.com/posters/last-horizon.jpg",
      "backdropUrl": "https://example.com/backdrops/last-horizon.jpg",
      "year": 2025,
      "rating": 8.9,
      "genres": ["Sci-Fi", "Adventure"],
      "overview": "A cartographer maps a sea that redraws itself every night.",
      "status": "ongoing",
      "episodes": [
        {
          "number": 1,
          "title": "The Sea That Moves",
          "videoUrl": "https://example.com/videos/last-horizon-e1.mp4",
          "durationSeconds": 1420
        }
      ]
    },
    {
      "id": "paper-moons",
      "type": "manga",
      "title": "Paper Moons",
      "year": 2022,
      "rating": 8.7,
      "genres": ["Romance", "Drama"],
      "overview": "A paper artist folds a moon for the girl across the street.",
      "status": "ongoing",
      "chapters": [
        {
          "number": 1,
          "title": "The First Fold",
          "pageUrls": [
            "https://example.com/pages/paper-moons-1-1.jpg",
            "https://example.com/pages/paper-moons-1-2.jpg"
          ]
        }
      ]
    }
  ]
}
```

### Field table

**Top level**

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | **yes** | Display name in Settings → Providers. Max 100 characters. |
| `version` | integer | no | Informational only; the parser ignores it. |
| `items` | array of item objects | **yes** | May be empty (`[]`), max 1000 items. |

**Item**

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | **yes** | Unique within the repo. Stable across updates — library entries and history point at it. |
| `type` | string | **yes** | Exactly one of `anime`, `movie`, `manga`, `manhwa`. |
| `title` | string | **yes** | Display title. |
| `posterUrl` | string | no | Poster image URL. |
| `backdropUrl` | string | no | Wide backdrop image URL (details hero). |
| `year` | integer | no | Release year, e.g. `2025`. |
| `rating` | number | no | 0–10. |
| `genres` | array of strings | no | e.g. `["Action", "Drama"]`. |
| `overview` | string | no | Short description shown on the details screen. |
| `status` | string | no | Free-form, e.g. `ongoing`, `completed`. |
| `episodes` | array of episode objects | no | For `anime` / `movie` (a movie is one episode: the full film). |
| `chapters` | array of chapter objects | no | For `manga` / `manhwa`. |

**Episode**

| Field | Type | Required | Notes |
|---|---|---|---|
| `number` | integer | **yes** | Episode number (1-based). |
| `title` | string | no | Episode title. |
| `videoUrl` | string | no | Direct video file URL (MP4 etc.) or a YouTube link. No extraction is ever performed — the URL must point at the video itself. |
| `durationSeconds` | integer | no | Length in seconds (progress + "resume from"). |

**Chapter**

| Field | Type | Required | Notes |
|---|---|---|---|
| `number` | integer | **yes** | Chapter number (1-based). |
| `title` | string | no | Chapter title. |
| `pageUrls` | array of strings | no | Page image URLs in reading order. |

### Caps

| Limit | Value | What happens when exceeded |
|---|---|---|
| Repo file size | 5 MB | Fetch fails: "This repo file is too large…" |
| Items per repo | 1000 | Parse fails naming the count. |
| Episodes / chapters per item | 1000 | Parse fails naming the item. |
| Fetch timeout | 15 s | Fetch fails: "The request timed out…" |

If any validation rule fails, the whole repo is rejected and nothing is
saved; the error message names the exact item and field.

### Hosting a repo

Any static host that serves the file over HTTPS with a `.json` URL works.
The app requires the URL to end in `.json`.

1. **GitHub** — put `catalog.json` in any public repo, then use the raw URL:
   `https://raw.githubusercontent.com/<user>/<repo>/<branch>/catalog.json`.
   Update the file in GitHub and the app picks it up on Refresh.
2. **GitHub Gist** — create a public gist with a `catalog.json` file, open
   the file's **Raw** view and copy that URL (it ends in `.json`).
3. **Pastebin** — paste the JSON, then use the **Raw** link. Note: raw
   Pastebin URLs do not end in `.json`; use the "Download" style link or
   prefer GitHub/Gist. If the URL does not end in `.json`, the app refuses
   it — paste the JSON in-app instead (see below).

### Adding a repo in the app

1. **Settings → Providers → Add provider.**
2. **Add via URL** — paste the `https://…/*.json` URL and tap Add provider.
   The app fetches it, validates it, and shows the exact error if anything
   is wrong.
3. **Paste JSON** — paste the JSON text directly. Useful for hosts whose
   URLs don't end in `.json`. Pasted repos can't be refreshed later — remove
   and re-add them with the new JSON. **Load example** fills in the bundled
   sample repo so you can see the format.

Repo rows show the item count and last-updated time. The toggle disables a
repo (its items disappear from Home/Search but stay cached). **Refresh**
re-downloads the file and replaces that repo's items. The built-in Sample
Catalog can't be deleted, but it can be turned off.

## Sample repo

`sample-repo.json` (project root, ready to host) and
`assets/sample-repo.json` (bundled in the app) are the same file: the
**Sample Catalog** — 24 fictional titles (anime, movies, manga, manhwa)
with the bundled artwork. Both are **generated** from
`lib/data/sample_provider.dart` — never edit them by hand:

```bash
dart tool/generate_sample_repo.dart
```

To try it hosted: upload `sample-repo.json` to a GitHub repo or Gist and
add its raw `.json` URL in Settings → Providers → Add provider.

## Run it (VS Code)

### 1. Install the tools

- **Flutter SDK** (stable, 3.50.0 or newer) — https://docs.flutter.dev/get-started/install
  - Unzip it, add `flutter/bin` to your `PATH`, run `flutter doctor`.
- **Android Studio** (for the Android SDK + an emulator or a real device) —
  https://developer.android.com/studio
  - Open Android Studio → SDK Manager → install the Android SDK
    (API 34+) and accept the licenses (`flutter doctor --android-licenses`).
  - VS Code: install the **Flutter** extension (it pulls in the Dart one).

### 2. Run on a phone / emulator

```bash
cd streambox-flutter-app
flutter pub get
flutter run
```

Pick your device when prompted (or `flutter run -d <device-id>`; list them
with `flutter devices`). Hot reload with `r`, hot restart with `R`.

### 3. Build a release APK (on your own machine)

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Copy that file to your phone and install it. Without a `key.properties`
file this is a **debug-signed** release APK — good for personal use and
testing. For a release-signed APK (fewer install warnings), see
[Release signing](#release-signing) below. A Play Store release needs an
AAB instead: `flutter build appbundle`.

### 4. Web preview

```bash
flutter run -d chrome
```

The web build is a compile/preview check — the app is designed for phone
and TV. Video playback and file backup work in the browser, but secure
storage and immersive mode are Android-only.

## Get an APK without building locally (GitHub Actions)

No Android SDK needed — GitHub builds it for you:

1. Create a repo on GitHub and push this project to the `main` branch.
2. Open the repo → **Actions** tab → the **Build APK** workflow runs on
   every push to `main` (or start it manually with **Run workflow**).
3. When it finishes, open the run → **Artifacts** → download
   **`streambox-apk`** → install `app-release.apk` on your phone.

The workflow (`.github/workflows/build-apk.yml`) runs `flutter pub get`,
`flutter analyze`, `flutter test`, then `flutter build apk --release`.
**The first run needs no secrets** — there are no API keys in this project
at all, so nothing to configure.

## Release signing

APKs built without signing secrets use the **debug keys**, and Android /
Play Protect warns aggressively when installing them. A release-signed
APK (same code, signed with the project's release keystore) installs with
a much lighter warning. The keystore already exists in this project
(`android/streambox-release.keystore`) — it is **gitignored and travels
in the ZIP only**, never in the repo.

### One-time setup (GitHub Actions builds)

`android/keystore-passwords.txt` (ZIP-only, never committed) holds the
keystore alias, both passwords, the base64 of the keystore, and the exact
steps. In short — in your GitHub repo, go to **Settings → Secrets and
variables → Actions → New repository secret** and add these four:

| Secret name | Value (from `keystore-passwords.txt`) |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 blob (one long line) |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `streambox` |
| `ANDROID_KEY_PASSWORD` | the key password |

The next workflow run signs the APK with the release key. If any secret
is missing, the workflow still succeeds and falls back to debug signing
with a warning — the build never fails on signing.

### Local release-signed builds

Create `android/key.properties` (gitignored) next to the keystore:

```properties
storePassword=<the store password>
keyPassword=<the key password>
keyAlias=streambox
storeFile=../streambox-release.keystore
```

Then `flutter build apk --release` signs with the release key.

### Rotating the key

If the keystore or its passwords ever leak, generate a new one and update
the secrets + `keystore-passwords.txt`:

```bash
keytool -genkeypair -v -keystore android/streambox-release.keystore \
  -alias streambox -keyalg RSA -keysize 2048 -validity 10000
```

**Warning:** Android treats a new signing key as a *different app* — users
must uninstall the old APK before installing one signed with a new key.
Keep a safe backup of the keystore and its passwords; if the keystore is
lost, future updates can never be installed over the old app.

### Honest note about install warnings

A sideloaded APK (installed from a file, not from the Play Store) **always**
shows Android's "unknown sources" prompt — that is Android itself, and no
signing setup removes it. Release signing reduces the extra Play Protect
warning; only Play Store distribution removes install warnings entirely.

## Android TV notes

- The app declares the Leanback launcher category and a TV banner, and
  `android.hardware.touchscreen` is not required, so it appears in the TV
  launcher.
- Cards and the bottom nav are D-pad focusable (`FocusableCard` — focus ring
  + Enter/Space activation).
- **No TV device test has been done in this VM** — the Leanback manifest and
  focus widgets are in place, but real D-pad navigation, the 10-foot layout
  and TV playback still need testing on an actual Android TV / Fire TV
  device.

## iOS notes

- Standard Flutter iOS target: bundle id `com.kizoo.streambox`, display
  name `StreamBox`. Build it on a Mac with Xcode (`flutter build ios`) or
  with a macOS GitHub Actions runner.
- **No iOS build verification was possible in this VM** (no Mac, no Xcode)
  — the iOS target is untested until it is built on Apple hardware.

## What this app does NOT do

- No TMDB / Jikan / AniList — StreamBox talks to no third-party metadata
  API at all. All catalog data comes from JSON repos you add yourself.
- No extensions, no scrapers, no video-URL extraction, no sideloaded
  provider packages. A repo is a JSON catalog, nothing more.
- No demo login and no shared account — auth is a local sign-up + device
  code, and every user's data stays on their own device.
- No server, no analytics, no ads, no tracking.
- Only use repos you trust, and only list content you have the right to
  share. The sample data in this project is fictional.

## Development

```bash
flutter pub get          # install dependencies
flutter analyze          # must be 0 issues
flutter test             # 101 tests (unit + widget)
flutter build web --release   # smoke build (delete build/ after)
```

After changing a Hive model, regenerate the adapters (committed to the repo):

```bash
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` is **pinned to 2.4.13** on purpose — newer versions pull an
analyzer that needs the `_macros` SDK package Dart 3.14 no longer ships, so
pub resolution fails. Do not upgrade it without also replacing
`hive_generator` (or hand-writing the adapters). See `CONTRACT.md` for the
workstream contracts: routes, Hive typeIds, box names, i18n rules and theme
tokens.

## Honest limits (please read before judging it on a phone)

- **No device test has been done anywhere yet.** The app is verified by
  `flutter analyze` (0 issues), 117 passing tests and a release web build.
  The first real run on a phone may surface layout, playback or storage
  issues — that is the next step.
- **The web build is a compile check only** — it proves the app builds and
  serves; it is not a substitute for running on Android.
- **No APK has been built in this VM** (no Android SDK here). The first real
  APK comes from GitHub Actions or a local `flutter build apk`.
- **Notifications are in-app only** — there are no push notifications and no
  scheduled reminder in this build; the Settings toggle covers in-app
  notices only.
- **Reader brightness is not persisted** — it resets to full brightness
  every time the reader opens (the setting is in-memory only).
- **Repo error messages are English-only** — provider fetch/parse errors
  show the raw English message even in Bangla mode.
- **The launcher icon is a designed logo mark** — orange gradient
  (#FF7700→#F03A02) with a white play triangle, generated by
  `tool/generate_brand_assets.py` (same script makes the Android TV
  banner). Regenerate platform icons with
  `dart run flutter_launcher_icons` after changing
  `assets/icon/icon.png`.
- **Startup is hardened against white screens** — if local storage cannot
  start, the app shows a branded error screen with a Retry button instead
  of a blank screen; the splash session check has an 8s timeout per step,
  so a hanging secure-storage read can never strand the app. Hive init
  tries pure-Dart direct Android app-data paths first (no platform
  channel — this is what saves a device whose whole path_provider layer
  is broken, as seen on v1.0.2), then the documents, support, temp and
  cache directories; the error screen shows the full error with a Copy
  button.
- **Auth survives a broken KeyStore** — credentials normally live in
  flutter_secure_storage; if secure storage throws on a device, sign-up,
  login, session and onboarding fall back to a dedicated `authFallback`
  Hive box (`ResilientCredentialStorage`). The fallback holds the same
  salted SHA-256 hashes — never a plaintext password or code — so the
  only thing that degrades is the container (a plain Hive file instead of
  the OS keystore), and only on devices whose keystore is already broken.
  On a healthy device the fallback box stays empty.
- **Sideloaded APKs always show Android's "unknown sources" prompt** —
  release signing (see above) reduces the extra Play Protect warning, but
  only Play Store distribution removes install warnings entirely.
- **No screenshot/widget tests for most screens** — widget tests cover
  shared components plus the full-app startup path
  (`test/startup*.dart`: boot, splash, routing, secure-storage failure
  and hang); other screens are covered by unit tests of their logic plus
  the web-build smoke check.
- **iOS and Android TV are untested** (see above).
