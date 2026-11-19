# Provider repo format

StreamBox providers are **JSON catalogs ONLY**: one JSON file per repo,
fetched over HTTP(S) and parsed into anime, movie, manga and manhwa titles.
There are no extensions, no scrapers and no video-URL extraction — a repo is
just a list of titles with the links the repo author chose to include.

One JSON file may hold **one catalog or several providers** (multi-catalog,
v1.0.4): each provider in the file becomes its own row in Settings →
Providers, which you can enable/disable/delete individually. See
[Multi-catalog files](#multi-catalog-files).

- Bundled example: `assets/sample-repo.json` (also at the project root as
  `sample-repo.json`, ready to host). In the app, **Settings → Providers →
  Add provider → Paste JSON → Load example** fills it in.
- The sample data is the single source of truth in
  `lib/data/sample_provider.dart`; the JSON files are generated from it with
  `dart tool/generate_sample_repo.dart` — never edit them by hand.
- Parser: `HiveProviderService.parseRepoDocument` in
  `lib/services/provider_service.dart`. Every rule below is enforced there,
  with a user-facing error message naming the exact problem.

## Minimal example

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

## Multi-catalog files

A single JSON file can carry several providers. Two shapes are accepted —
an object with a `providers` list, or a top-level array of catalog objects.
Each catalog has the same shape as a single-catalog file (`name` + `items`,
see the field table below), and each becomes its own repo row with its own
item count, toggle and delete button. Refreshing any row re-syncs every
provider from that file; a provider removed from the file disappears from
the list on the next refresh.

```json
{
  "providers": [
    {
      "name": "Anime Hub",
      "items": [
        {
          "id": "last-horizon",
          "type": "anime",
          "title": "Last Horizon",
          "year": 2025,
          "episodes": [
            {
              "number": 1,
              "title": "The Sea That Moves",
              "videoUrl": "https://example.com/videos/last-horizon-e1.mp4"
            }
          ]
        }
      ]
    },
    {
      "name": "Manga Vault",
      "items": [
        {
          "id": "paper-moons",
          "type": "manga",
          "title": "Paper Moons",
          "year": 2022,
          "chapters": [
            {
              "number": 1,
              "title": "The First Fold",
              "pageUrls": ["https://example.com/pages/paper-moons-1-1.jpg"]
            }
          ]
        }
      ]
    }
  ]
}
```

The same two providers as a top-level array:

```json
[
  { "name": "Anime Hub", "items": [ /* … */ ] },
  { "name": "Manga Vault", "items": [ /* … */ ] }
]
```

Rules for multi-catalog files:

- Every catalog needs its own `name` and `items` — the same validation
  rules apply per catalog, and an error names the catalog that failed,
  e.g. `Provider #2 is missing a "name".`
- Item ids only need to be unique *within* their own catalog — two
  catalogs in one file may both have an item with id `show-1`.
- Max 50 providers per file; each catalog still caps at 1000 items.
- A file that grows from one catalog to several keeps the first catalog's
  id, so library entries and history for it survive.

## Field table

### Top level

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | **yes** | Display name in Settings → Providers. Max 100 characters. Required for a single-catalog file and for every catalog in a multi-catalog file. |
| `version` | integer | no | Informational only; the parser ignores it. |
| `items` | array of item objects | **yes** | May be empty (`[]`), max 1000 items. Required per catalog. |
| `providers` | array of catalog objects | no | Multi-catalog shape: when present, the file holds one provider per entry (max 50) and the top-level `name`/`items` are not used. |

### Item

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | **yes** | Unique within the repo. Stable across updates — library entries and history point at it. |
| `type` | string | **yes** | Exactly one of `anime`, `movie`, `manga`, `manhwa`. |
| `title` | string | **yes** | Display title. |
| `posterUrl` | string | no | Poster image URL. Bundled-asset paths (`assets/artwork/…`) work for the sample catalog only. |
| `backdropUrl` | string | no | Wide backdrop image URL (details hero). |
| `year` | integer | no | Release year, e.g. `2025`. |
| `rating` | number | no | 0–10. |
| `genres` | array of strings | no | e.g. `["Action", "Drama"]`. |
| `overview` | string | no | Short description shown on the details screen. |
| `status` | string | no | Free-form, e.g. `ongoing`, `completed`. |
| `episodes` | array of episode objects | no | For `anime` / `movie` (a movie is one episode: the full film). |
| `chapters` | array of chapter objects | no | For `manga` / `manhwa`. |

### Episode

| Field | Type | Required | Notes |
|---|---|---|---|
| `number` | integer | **yes** | Episode number (1-based). |
| `title` | string | no | Episode title. |
| `videoUrl` | string | no | Direct video file URL (MP4 etc.) played by the player. No extraction is ever performed — the URL must point at the video itself. |
| `youtubeId` | string | no | YouTube video id (the 11-character id from a youtube.com/watch?v=… URL), played as an embedded YouTube video. When an episode has both `youtubeId` and `videoUrl`, YouTube wins. |
| `durationSeconds` | integer | no | Length in seconds (progress + "resume from"). |

### Chapter

| Field | Type | Required | Notes |
|---|---|---|---|
| `number` | integer | **yes** | Chapter number (1-based). |
| `title` | string | no | Chapter title. |
| `pageUrls` | array of strings | no | Page image URLs in reading order. |

## Validation rules

The parser rejects the whole file (nothing is saved) when any rule fails,
and the error message names the exact problem — e.g.
`Item "last-horizon" has an unknown type "series". Use one of: anime, movie,
manga, manhwa.` In a multi-catalog file the message also names the catalog,
e.g. `Provider #2 ("Manga Vault"): Item "paper-moons" …`.

- The file must be valid JSON. A leading UTF-8 byte-order mark (BOM, as
  saved by Windows Notepad) is tolerated.
- The root must be a single-catalog object (`{"name": …, "items": […]}`),
  a multi-catalog object (`{"providers": […]}`), or a top-level array of
  catalog objects.
- `name` must be a non-empty string (max 100 chars), per catalog.
- `items` must be present and be a list, per catalog.
- Every item needs a non-empty `id` (unique in its catalog), a non-empty
  `title`, and a `type` of `anime` / `movie` / `manhwa` / `manga`.
- `year` must be a whole number; `rating` a number from 0 to 10; `genres`
  an array of strings; `posterUrl` / `backdropUrl` / `overview` / `status`
  strings when present.
- Every episode needs an integer `number`; `title` / `videoUrl` /
  `youtubeId` must be strings and `durationSeconds` an integer when present.
- Every chapter needs an integer `number`; `title` must be a string and
  `pageUrls` an array of strings when present.
- A file that looks like an **extension index** (entries with `pkg` / `apk`
  / `packageName` fields, or `extensions` / `apps` lists) is rejected with
  a message saying extension files are not supported. Providers are JSON
  catalogs of titles — see [Boundaries](#boundaries).

## Caps

| Limit | Value | What happens when exceeded |
|---|---|---|
| Repo file size | 5 MB | Fetch fails: "This repo file is too large…" |
| Providers per file | 50 | Parse fails naming the count. |
| Items per repo | 1000 | Parse fails naming the count. |
| Episodes / chapters per item | 1000 | Parse fails naming the item. |
| Fetch timeout | 15 s | Fetch fails: "The request timed out…" |

## Hosting a repo

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

## Adding a repo in the app

1. **Settings → Providers → Add provider.**
2. **Add via URL** — paste the `https://…/*.json` URL and tap Add provider.
   The app fetches it, validates it, and shows the exact error if anything
   is wrong. A multi-catalog file adds one row per provider.
3. **Paste JSON** — paste the JSON text directly. Useful for hosts whose
   URLs don't end in `.json`. Pasted repos can't be refreshed later — remove
   and re-add them with the new JSON. **Load example** fills in the bundled
   sample repo (single-catalog) so you can see the format.

Repo rows show the item count and last-updated time. The toggle disables a
repo (its items disappear from Home/Search but stay cached). **Refresh**
re-downloads the file and replaces that repo's items — for a multi-catalog
file it re-syncs every provider from the file at once. The built-in Sample
Catalog can't be deleted, but it can be turned off.

## Boundaries

- A repo is a **catalog**, not a source: it lists titles and the direct
  video/page URLs the author provides. StreamBox never scrapes pages,
  extracts video URLs, loads extensions (no binary index files, no APK
  sideloading) or talks to any third-party metadata API.
- Only use repos you trust, and only list content you have the right to
  share. Sample data in this project is fictional.
