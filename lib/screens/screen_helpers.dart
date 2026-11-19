import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';

/// Shared helpers for the screens workstream: navigation to details /
/// player / reader, type + status labels, artwork fallbacks and snackbars.
///
/// Route parameter convention (CONTRACT.md §4): `:id` is the catalog box
/// key `"$providerId::$itemId"`. Player/reader take the episode/chapter
/// number as a query parameter (`?episode=3` / `?chapter=5`) — the
/// player-reader workstream reads them from `state.uri.queryParameters`.

/// Fallback poster when an item has no artwork at all.
const String kFallbackPoster = 'assets/artwork/last-horizon-poster.jpg';

/// Fallback backdrop when an item has no backdrop art.
const String kFallbackBackdrop = 'assets/artwork/hero-last-horizon.jpg';

/// Best poster art for [item]: poster, then backdrop, then the bundled
/// fallback — cards never render a blank box.
String posterOf(ProviderItem item) {
  if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
    return item.posterUrl!;
  }
  if (item.backdropUrl != null && item.backdropUrl!.isNotEmpty) {
    return item.backdropUrl!;
  }
  return kFallbackPoster;
}

/// Best backdrop art for [item]: backdrop, then poster, then the bundled
/// fallback.
String backdropOf(ProviderItem item) {
  if (item.backdropUrl != null && item.backdropUrl!.isNotEmpty) {
    return item.backdropUrl!;
  }
  if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
    return item.posterUrl!;
  }
  return kFallbackBackdrop;
}

/// True for manga/manhwa (read in the reader); false for anime/movie
/// (played in the player).
bool isReadable(ContentType type) =>
    type == ContentType.manga || type == ContentType.manhwa;

/// Localised type label (Anime / Movies / Manga / Manhwa).
String typeLabel(BuildContext context, ContentType type) {
  switch (type) {
    case ContentType.anime:
      return tr(context, 'search.typeAnime');
    case ContentType.movie:
      return tr(context, 'search.typeMovie');
    case ContentType.manga:
      return tr(context, 'search.typeManga');
    case ContentType.manhwa:
      return tr(context, 'search.typeManhwa');
  }
}

/// Localised status label: `ongoing` / `completed` map to keys, anything
/// else shows as-is (capitalised), null shows 'Unknown'.
String statusLabel(BuildContext context, String? status) {
  final value = status?.trim().toLowerCase();
  if (value == null || value.isEmpty) {
    return tr(context, 'details.statusUnknown');
  }
  if (value == 'ongoing') return tr(context, 'details.ongoing');
  if (value == 'completed') return tr(context, 'details.completed');
  return value[0].toUpperCase() + value.substring(1);
}

/// Push the details screen for [item].
void openDetails(BuildContext context, ProviderItem item) {
  context.push('/details/${Uri.encodeComponent(item.boxKey)}');
}

/// Push the video player for [item], optionally at [episode].
void openPlayer(BuildContext context, ProviderItem item, {int? episode}) {
  final id = Uri.encodeComponent(item.boxKey);
  if (episode != null) {
    context.push('/player/$id?episode=$episode');
  } else {
    context.push('/player/$id');
  }
}

/// Push the manga reader for [item], optionally at [chapter].
void openReader(BuildContext context, ProviderItem item, {int? chapter}) {
  final id = Uri.encodeComponent(item.boxKey);
  if (chapter != null) {
    context.push('/reader/$id?chapter=$chapter');
  } else {
    context.push('/reader/$id');
  }
}

/// Play (video) or Read (comic) — routes to the player or the reader.
void openPlay(BuildContext context, ProviderItem item,
    {int? episodeOrChapter}) {
  if (isReadable(item.type)) {
    openReader(context, item, chapter: episodeOrChapter);
  } else {
    openPlayer(context, item, episode: episodeOrChapter);
  }
}

/// Short floating confirmation (saved / removed / copied …).
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 0.0–1.0 watch/read progress for a history entry, or null when it
/// can't be computed (no duration / page count in the catalog).
double? watchProgress(HistoryEntry entry, ProviderItem item) {
  if (isReadable(item.type)) {
    final chapters = item.chapters;
    Map<String, dynamic>? chapter;
    for (final c in chapters) {
      if ((c['number'] as num?)?.toInt() == entry.episodeOrChapter) {
        chapter = c;
      }
    }
    final pages = chapter?['pageUrls'];
    if (pages is List && pages.isNotEmpty && entry.page > 0) {
      return (entry.page / pages.length).clamp(0.0, 1.0);
    }
    return null;
  }
  final episodes = item.episodes;
  Map<String, dynamic>? episode;
  for (final e in episodes) {
    if ((e['number'] as num?)?.toInt() == entry.episodeOrChapter) {
      episode = e;
    }
  }
  final duration = (episode?['durationSeconds'] as num?)?.toInt();
  if (duration != null && duration > 0 && entry.positionSeconds > 0) {
    return (entry.positionSeconds / duration).clamp(0.0, 1.0);
  }
  return null;
}

/// Initials for an avatar circle: first letters of the first two name
/// parts, upper-cased; '?' when the name is empty.
String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}
