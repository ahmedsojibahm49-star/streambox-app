# Provider repo format

StreamBox providers are **JSON catalogs ONLY**: one JSON file per repo,
fetched over HTTP(S) and parsed into anime, movie, manga and manhwa titles.
There are no extensions, no scrapers and no video-URL extraction — a repo is
just a list of titles with the links the repo author chose to include.

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

## Field table

### Top level

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | **yes** | Display name in Settings → Providers. Max 100 characters. |
| `version` | integer | no | Informational only; the parser ignores it. |
| `items` | array of item objects | **yes** | May be empty (`[]`), max 1000 items. |

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

The parser rejects the whole repo (nothing is saved) when any rule fails,
and the error message names the exact item and field — e.g.
`Item "last-horizon" has an unknown type "series". Use one of: anime, movie,
manga, manhwa.`

- The file must be valid JSON and the root must be an object.
- `name` must be a non-empty string (max 100 chars).
- `items` must be present and be a list.
- Every item needs a non-empty `id` (unique in the repo), a non-empty
  `title`, and a `type` of `anime` / `movie` / `manhwa` / `manga`.
- `year` must be a whole number; `rating` a number from 0 to 10; `genres`
  an array of strings; `posterUrl` / `backdropUrl` / `overview` / `status`
  strings when present.
- Every episode needs an integer `number`; `title` / `videoUrl` /
  `youtubeId` must be strings and `durationSeconds` an integer when present.
- Every chapter needs an integer `number`; `title` must be a string and
  `pageUrls` an array of strings when present.

## Caps

| Limit | Value | What happens when exceeded |
|---|---|---|
| Repo file size | 5 MB | Fetch fails: "This repo file is too large…" |
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
   is wrong.
3. **Paste JSON** — paste the JSON text directly. Useful for hosts whose
   URLs don't end in `.json`. Pasted repos can't be refreshed later — remove
   and re-add them with the new JSON. **Load example** fills in the bundled
   sample repo so you can see the format.

Repo rows show the item count and last-updated time. The toggle disables a
repo (its items disappear from Home/Search but stay cached). **Refresh**
re-downloads the file and replaces that repo's items. The built-in Sample
Catalog can't be deleted, but it can be turned off.

## Boundaries

- A repo is a **catalog**, not a source: it lists titles and the direct
  video/page URLs the author provides. StreamBox never scrapes pages,
  extracts video URLs, loads extensions (no binary index files, no APK
  sideloading) or talks to any third-party metadata API.
- Only use repos you trust, and only list content you have the right to
  share. Sample data in this project is fictional.
