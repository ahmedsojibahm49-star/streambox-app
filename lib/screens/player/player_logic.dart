/// Which plugin plays an episode. Decided ONLY from the URLs/ids the
/// provider JSON supplies — never extracted, scraped or guessed.
enum PlaybackSourceType {
  /// Direct mp4 / HLS URL played with video_player.
  direct,

  /// YouTube video id played with youtube_player_flutter.
  youtube,

  /// The episode carries no playable source at all.
  none,
}

/// A resolved playback source for one episode.
class PlaybackSource {
  const PlaybackSource.direct(this.videoUrl)
      : type = PlaybackSourceType.direct,
        youtubeId = null;

  const PlaybackSource.youtube(this.youtubeId)
      : type = PlaybackSourceType.youtube,
        videoUrl = null;

  const PlaybackSource.none()
      : type = PlaybackSourceType.none,
        videoUrl = null,
        youtubeId = null;

  final PlaybackSourceType type;

  /// Direct video URL (mp4/HLS), only when [type] is [PlaybackSourceType.direct].
  final String? videoUrl;

  /// YouTube video id, only when [type] is [PlaybackSourceType.youtube].
  final String? youtubeId;

  bool get hasSource => type != PlaybackSourceType.none;

  /// URL opened by the "Open in browser" fallback. Null when there is no
  /// source to open.
  String? get browserUrl {
    switch (type) {
      case PlaybackSourceType.direct:
        return videoUrl;
      case PlaybackSourceType.youtube:
        return youtubeWatchUrl(youtubeId!);
      case PlaybackSourceType.none:
        return null;
    }
  }
}

/// Resolve which plugin plays [episode].
///
/// Priority: a non-empty `youtubeId` wins (YouTube embeds are the most
/// reliable source a repo can supply); otherwise a non-empty `videoUrl`
/// plays directly; otherwise there is no source.
///
/// [sourceHint] is the optional `source` query param on the `/player/:id`
/// route (`youtube` or `direct`/`video`). When it names a source the episode
/// actually has, it wins over the default priority; when it names a source
/// the episode lacks, it is ignored and auto-resolution applies.
PlaybackSource resolvePlaybackSource(
  Map<String, dynamic> episode, {
  String? sourceHint,
}) {
  final youtubeId = _stringField(episode, 'youtubeId');
  final videoUrl = _stringField(episode, 'videoUrl');

  final hint = sourceHint?.trim().toLowerCase();
  if (hint == 'youtube' && youtubeId != null) {
    return PlaybackSource.youtube(youtubeId);
  }
  if ((hint == 'direct' || hint == 'video') && videoUrl != null) {
    return PlaybackSource.direct(videoUrl);
  }

  if (youtubeId != null) return PlaybackSource.youtube(youtubeId);
  if (videoUrl != null) return PlaybackSource.direct(videoUrl);
  return const PlaybackSource.none();
}

/// `https://www.youtube.com/watch?v=...` for the browser fallback.
String youtubeWatchUrl(String videoId) =>
    'https://www.youtube.com/watch?v=$videoId';

/// Episode number from an episode map. Falls back to [fallback] (the list
/// position + 1) when the map has no usable `number` field.
int episodeNumber(Map<String, dynamic> episode, {int fallback = 1}) {
  final raw = episode['number'];
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw.toInt() > 0) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed > 0) return parsed;
  }
  return fallback;
}

/// Episode title from an episode map. Empty when the map has no title.
String episodeTitle(Map<String, dynamic> episode) =>
    _stringField(episode, 'title') ?? '';

/// Declared runtime in seconds, or 0 when the repo does not supply one.
int episodeDurationSeconds(Map<String, dynamic> episode) {
  final raw = episode['durationSeconds'];
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw.toInt() > 0) return raw.toInt();
  return 0;
}

/// Index of the episode with [number] in [episodes], or 0 when [number] is
/// null or no episode has that number. Never out of range.
int episodeIndexFor(List<Map<String, dynamic>> episodes, int? number) {
  if (episodes.isEmpty) return 0;
  if (number != null) {
    for (var i = 0; i < episodes.length; i++) {
      if (episodeNumber(episodes[i], fallback: i + 1) == number) return i;
    }
  }
  return 0;
}

/// Index of the next episode after [currentIndex], or null at the end.
int? nextEpisodeIndex(int episodeCount, int currentIndex) {
  if (currentIndex < 0 || currentIndex + 1 >= episodeCount) return null;
  return currentIndex + 1;
}

/// Index of the previous episode before [currentIndex], or null at the start.
int? previousEpisodeIndex(int currentIndex) {
  if (currentIndex <= 0) return null;
  return currentIndex - 1;
}

/// Clamp a seek target into `[0, duration]`. A zero/unknown duration
/// clamps everything to zero.
Duration clampSeek(Duration target, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  if (target <= Duration.zero) return Duration.zero;
  if (target >= duration) return duration;
  return target;
}

/// Skip [seconds] (negative = backwards) from [current], clamped to the
/// video bounds.
Duration seekBy(Duration current, Duration duration, int seconds) =>
    clampSeek(current + Duration(seconds: seconds), duration);

/// Resume position in seconds for a saved [savedSeconds] against a video of
/// [durationSeconds].
///
/// Returns 0 when there is nothing worth resuming: no saved position, an
/// unknown duration, a saved position at/past the end, or a saved position
/// within the last 10 seconds (the episode is effectively finished — start
/// from the beginning instead of the credits).
int resumePositionSeconds({
  required int savedSeconds,
  required int durationSeconds,
}) {
  if (savedSeconds <= 0) return 0;
  if (durationSeconds <= 0) return savedSeconds;
  if (savedSeconds >= durationSeconds) return 0;
  if (durationSeconds - savedSeconds <= 10) return 0;
  return savedSeconds;
}

/// Playback progress as a 0.0–1.0 fraction. 0 when the duration is unknown.
double progressFraction(int positionSeconds, int durationSeconds) {
  if (durationSeconds <= 0 || positionSeconds <= 0) return 0;
  if (positionSeconds >= durationSeconds) return 1;
  return positionSeconds / durationSeconds;
}

/// True when the up-next card should appear: there IS a next episode and
/// playback has ended or is within the last 15 seconds.
bool shouldShowUpNext({
  required Duration position,
  required Duration duration,
  required bool hasNext,
}) {
  if (!hasNext || duration <= Duration.zero) return false;
  return duration - position <= const Duration(seconds: 15);
}

/// Split a catalog box key (`"$providerId::$itemId"`) into its parts.
/// Returns null when the key has no `::` separator.
({String providerId, String itemId})? parseBoxKey(String boxKey) {
  final separator = boxKey.indexOf('::');
  if (separator <= 0 || separator + 2 >= boxKey.length) return null;
  return (
    providerId: boxKey.substring(0, separator),
    itemId: boxKey.substring(separator + 2),
  );
}

String? _stringField(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}
