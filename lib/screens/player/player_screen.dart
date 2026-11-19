import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../i18n/i18n.dart';
import '../../models/models.dart';
import '../../providers/catalog_providers.dart';
import '../../services/library_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/focusable_card.dart';
import '../../widgets/player_controls.dart';
import 'player_logic.dart';

/// Video player for anime episodes and movies (route `/player/:id`).
///
/// Plays ONLY the source the provider JSON supplies for the episode:
/// `youtubeId` → YouTube embed, `videoUrl` → direct mp4/HLS via
/// video_player, neither → error state. No URL extraction, no scraping.
///
/// Query params: `episode` (episode number, defaults to the first) and
/// `source` (optional `youtube`/`direct` hint — see [resolvePlaybackSource]).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    this.episodeNumber,
    this.sourceHint,
  });

  /// Catalog box key of the item (`"$providerId::$itemId"`).
  final String itemId;

  /// Episode number to start on (from the `episode` query param).
  final int? episodeNumber;

  /// Preferred source hint (from the `source` query param).
  final String? sourceHint;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  ProviderItem? _item;
  ({String providerId, String itemId})? _keyParts;

  int _episodeIndex = 0;
  PlaybackSource _source = const PlaybackSource.none();

  VideoPlayerController? _videoController;
  YoutubePlayerController? _ytController;
  StreamSubscription<YoutubePlayerValue>? _ytValueSub;
  StreamSubscription<YoutubeVideoState>? _ytStateSub;

  bool _initializing = true;
  bool _isPlaying = false;
  bool _ended = false;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  bool _scrubbing = false;
  String? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _speed = 1.0;

  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _notFoundTimer;

  List<Map<String, dynamic>> get _episodes => _item?.episodes ?? const [];

  Map<String, dynamic>? get _currentEpisode =>
      _episodes.isEmpty ? null : _episodes[_episodeIndex];

  int get _currentEpisodeNumber => _currentEpisode == null
      ? 1
      : episodeNumber(_currentEpisode!, fallback: _episodeIndex + 1);

  bool get _hasNextEpisode =>
      nextEpisodeIndex(_episodes.length, _episodeIndex) != null;

  @override
  void initState() {
    super.initState();
    _keyParts = parseBoxKey(widget.itemId);
    if (_keyParts == null) {
      _initializing = false;
      _error = 'player.itemNotFound';
    } else {
      // Resolve via the catalog provider (it also triggers the lazy
      // sample-catalog seed). The item may arrive a moment later — the
      // ref.listen in build() picks it up; only after a grace period do
      // we conclude the id is genuinely unknown.
      final item = ref.read(itemByIdProvider(widget.itemId));
      if (item != null) {
        _onItemLoaded(item);
      } else {
        _notFoundTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _item == null) {
            setState(() {
              _initializing = false;
              _error = 'player.itemNotFound';
            });
          }
        });
      }
    }
    // Save progress every 10s while playing (also saved on pause/dispose).
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isPlaying && _position > Duration.zero) _saveProgress();
    });
  }

  /// Called once when the catalog item resolves (immediately from initState
  /// or later via the ref.listen in build()).
  void _onItemLoaded(ProviderItem item) {
    _notFoundTimer?.cancel();
    if (_item != null) return;
    _item = item;
    if (_episodes.isEmpty) {
      setState(() {
        _initializing = false;
        _error = 'player.noVideo';
      });
      return;
    }
    _episodeIndex = episodeIndexFor(_episodes, widget.episodeNumber);
    _loadEpisode(_episodeIndex);
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _notFoundTimer?.cancel();
    _ytValueSub?.cancel();
    _ytStateSub?.cancel();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _ytController?.close();
    _restoreOrientation();
    super.dispose();
  }

  // -- Loading ---------------------------------------------------------------

  Future<void> _loadEpisode(int index) async {
    // Save progress for the episode being left behind.
    if (!_initializing && _position > Duration.zero) _saveProgress();

    await _disposeControllers();
    if (!mounted) return;

    setState(() {
      _episodeIndex = index;
      _initializing = true;
      _error = null;
      _ended = false;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
    });

    final episode = _episodes[index];
    final source = resolvePlaybackSource(
      episode,
      sourceHint: widget.sourceHint,
    );
    _source = source;

    if (!source.hasSource) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'player.noVideo';
      });
      return;
    }

    final resumeSeconds = _resumeSecondsFor(episode);

    if (source.type == PlaybackSourceType.direct) {
      await _loadDirect(source.videoUrl!, resumeSeconds);
    } else {
      _loadYoutube(source.youtubeId!, resumeSeconds);
    }
  }

  /// Saved position for this episode, or 0 when there is nothing to resume.
  int _resumeSecondsFor(Map<String, dynamic> episode) {
    final parts = _keyParts;
    if (parts == null) return 0;
    final entry = ref.read(libraryServiceProvider).progressFor(
          itemId: parts.itemId,
          providerId: parts.providerId,
        );
    if (entry == null) return 0;
    final number = episodeNumber(episode, fallback: _episodeIndex + 1);
    if (entry.episodeOrChapter != number) return 0;
    return resumePositionSeconds(
      savedSeconds: entry.positionSeconds,
      durationSeconds: episodeDurationSeconds(episode),
    );
  }

  Future<void> _loadDirect(String videoUrl, int resumeSeconds) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'player.videoFailed';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _videoController = controller;
    controller.addListener(_onVideoTick);
    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'player.videoFailed';
      });
      return;
    }
    if (!mounted) return;
    if (_videoController != controller) return; // superseded by a new load

    final realResume = resumePositionSeconds(
      savedSeconds: resumeSeconds,
      durationSeconds: controller.value.duration.inSeconds,
    );
    if (realResume > 0) {
      await controller.seekTo(Duration(seconds: realResume));
    }
    await controller.setPlaybackSpeed(_speed);
    await controller.play();
    setState(() {
      _initializing = false;
      _duration = controller.value.duration;
    });
    _scheduleHide();
  }

  void _loadYoutube(String videoId, int resumeSeconds) {
    final controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      startSeconds: resumeSeconds > 0 ? resumeSeconds.toDouble() : null,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
      ),
    );
    _ytController = controller;

    _ytValueSub = controller.stream.listen((value) {
      if (!mounted || _ytController != controller) return;
      final duration = value.metaData.duration;
      setState(() {
        if (duration > Duration.zero) _duration = duration;
        _isPlaying = value.playerState == PlayerState.playing;
        _ended = value.playerState == PlayerState.ended;
        if (value.hasError) _error = 'player.videoFailed';
        if (_isPlaying) {
          _initializing = false;
          _scheduleHide();
        }
        if (_ended) {
          _controlsVisible = true;
          _hideTimer?.cancel();
        }
      });
    });

    _ytStateSub = controller.videoStateStream.listen((state) {
      if (!mounted || _ytController != controller) return;
      if (_scrubbing) return;
      setState(() {
        _position = state.position;
        if (_duration > Duration.zero) {
          _buffered = Duration(
            milliseconds:
                (_duration.inMilliseconds * state.loadedFraction).round(),
          );
        }
      });
    });

    // YouTube has no initialize future — clear the spinner once the first
    // value arrives, or after a short grace period.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _ytController == controller && _initializing) {
        setState(() => _initializing = false);
      }
    });
    setState(() => _initializing = false);
  }

  Future<void> _disposeControllers() async {
    await _ytValueSub?.cancel();
    await _ytStateSub?.cancel();
    _ytValueSub = null;
    _ytStateSub = null;
    _videoController?.removeListener(_onVideoTick);
    await _videoController?.dispose();
    _videoController = null;
    await _ytController?.close();
    _ytController = null;
  }

  // -- Playback state ----------------------------------------------------------

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final ended = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
    setState(() {
      if (!_scrubbing) _position = value.position;
      _duration = value.duration;
      _buffered = value.buffered.isEmpty
          ? Duration.zero
          : value.buffered
              .map((r) => r.end)
              .reduce((a, b) => a > b ? a : b);
      _isPlaying = value.isPlaying;
      _ended = ended;
      if (value.hasError) _error = 'player.videoFailed';
      if (ended) {
        _controlsVisible = true;
        _hideTimer?.cancel();
      }
    });
  }

  Future<void> _togglePlay() async {
    if (_error != null || _initializing) return;
    if (_ended) {
      await _seekTo(Duration.zero);
      setState(() => _ended = false);
    }
    if (_isPlaying) {
      await _videoController?.pause();
      await _ytController?.pauseVideo();
      _saveProgress();
      setState(() {
        _isPlaying = false;
        _controlsVisible = true;
      });
      _hideTimer?.cancel();
    } else {
      await _videoController?.play();
      await _ytController?.playVideo();
      setState(() => _isPlaying = true);
      _scheduleHide();
    }
  }

  Future<void> _seekTo(Duration target) async {
    final clamped = clampSeek(target, _duration);
    await _videoController?.seekTo(clamped);
    await _ytController?.seekTo(
      seconds: clamped.inSeconds.toDouble(),
      allowSeekAhead: true,
    );
    setState(() => _position = clamped);
    _saveProgress();
  }

  Future<void> _skip(int seconds) async {
    await _seekTo(seekBy(_position, _duration, seconds));
    _scheduleHide();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _videoController?.setPlaybackSpeed(speed);
    await _ytController?.setPlaybackRate(speed);
    _scheduleHide();
  }

  void _playEpisode(int index) {
    if (index == _episodeIndex || index < 0 || index >= _episodes.length) {
      return;
    }
    _loadEpisode(index);
  }

  // -- Controls visibility ---------------------------------------------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying || _ended) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_ended) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _onVideoTap() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  // -- Fullscreen --------------------------------------------------------------

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _restoreOrientation();
      setState(() => _isFullscreen = false);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
      setState(() => _isFullscreen = true);
    }
    _scheduleHide();
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // -- Progress ----------------------------------------------------------------

  void _saveProgress() {
    final parts = _keyParts;
    if (parts == null || _item == null) return;
    final seconds = _ended ? 0 : _position.inSeconds;
    // Fire-and-forget: progress must never break playback.
    unawaited(
      ref.read(historyProvider.notifier).record(
            itemId: parts.itemId,
            providerId: parts.providerId,
            episodeOrChapter: _currentEpisodeNumber,
            positionSeconds: seconds,
          ),
    );
  }

  Future<void> _openInBrowser() async {
    final url = _source.browserUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // -- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // React to the catalog item arriving late (lazy sample-catalog seed),
    // disappearing (repo removed mid-playback), or refreshing (repo
    // re-fetch updates metadata). State changes run post-frame so a
    // provider notification during build can't call setState mid-build.
    ref.listen<ProviderItem?>(itemByIdProvider(widget.itemId),
        (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next != null && _item == null) {
          _onItemLoaded(next);
        } else if (next == null && _item != null) {
          unawaited(_disposeControllers());
          setState(() {
            _item = null;
            _error = 'player.itemNotFound';
            _initializing = false;
            _isPlaying = false;
          });
        } else if (next != null && _item != null) {
          setState(() => _item = next);
        }
      });
    });

    // Back exits fullscreen first instead of leaving the player.
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_isFullscreen,
          bottom: !_isFullscreen,
          child: _isFullscreen ? _buildVideoArea() : _buildPortrait(),
        ),
      ),
    );
  }

  Widget _buildPortrait() {
    return Column(
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: _buildVideoArea()),
        Expanded(child: _buildEpisodeList()),
      ],
    );
  }

  Widget _buildVideoArea() {
    final isYoutube = _source.type == PlaybackSourceType.youtube &&
        _ytController != null;
    if (isYoutube && !kIsWeb) {
      // On mobile the YouTube WebView lives in an OverlayPortal ABOVE the
      // normal widget tree, so the tap layer + controls must be built inside
      // the player's builder (which renders in that same overlay) — an
      // overlay in the outer Stack would sit underneath the WebView.
      return YoutubePlayer(
        controller: _ytController!,
        builder: (context, player, _) =>
            _buildStackedArea(videoChild: player),
      );
    }
    if (isYoutube && kIsWeb) {
      // On web, pointer events don't reach Flutter overlays through the
      // iframe, so YouTube's native controls stay (see the package docs).
      if (_error != null) {
        return _buildStackedArea(
          videoChild: const SizedBox.shrink(),
        );
      }
      return YoutubePlayer(controller: _ytController!);
    }
    return _buildStackedArea(videoChild: _buildDirectSurface());
  }

  /// Video surface + tap layer + controls + up-next + error, stacked.
  Widget _buildStackedArea({required Widget videoChild}) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          videoChild,
          _buildTapCatcher(),
          if (_initializing && _error == null)
            const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            ),
          if (_error != null) _buildErrorOverlay(),
          if (_error == null) _buildControlsOverlay(),
          if (_ended && _error == null) _buildUpNextCard(),
          if (!_ended &&
              _error == null &&
              shouldShowUpNext(
                position: _position,
                duration: _duration,
                hasNext: _hasNextEpisode,
              ))
            _buildUpNextChip(),
        ],
      ),
    );
  }

  Widget _buildDirectSurface() {
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// Transparent tap layer: tap anywhere on the video toggles the controls.
  Widget _buildTapCatcher() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onVideoTap,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xB3000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xB3000000),
              ],
              stops: [0.0, 0.3, 0.65, 1.0],
            ),
          ),
          child: Stack(
            children: [
              _buildTopBar(),
              _buildCenterControls(),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = _item?.title ?? '';
    final episode = _currentEpisode;
    final episodeLabel = episode == null
        ? ''
        : trParams(context, 'player.episode', {
            'number': _currentEpisodeNumber.toString(),
          });
    final subtitle = episode == null
        ? ''
        : [episodeLabel, episodeTitle(episode)]
            .where((s) => s.isNotEmpty)
            .join(' · ');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            PlayerControlButton(
              icon: Iconsax.arrow_left,
              label: tr(context, 'common.back'),
              onPressed: () {
                if (_isFullscreen) {
                  _toggleFullscreen();
                } else {
                  context.pop();
                }
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Positioned.fill(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlayerControlButton(
            icon: Iconsax.backward_10_seconds,
            label: tr(context, 'player.skipBack10'),
            onPressed: () => _skip(-10),
            size: 52,
            iconSize: 28,
          ),
          const SizedBox(width: 28),
          PlayPauseButton(
            isPlaying: _isPlaying,
            onPressed: _togglePlay,
            autofocus: true,
          ),
          const SizedBox(width: 28),
          PlayerControlButton(
            icon: Iconsax.forward_10_seconds,
            label: tr(context, 'player.skipForward10'),
            onPressed: () => _skip(10),
            size: 52,
            iconSize: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerSeekBar(
              position: _position,
              duration: _duration,
              buffered: _buffered,
              onSeek: _seekTo,
              onScrubStart: () => setState(() => _scrubbing = true),
              onScrubEnd: () {
                setState(() => _scrubbing = false);
                _scheduleHide();
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildSpeedButton(),
                const Spacer(),
                PlayerControlButton(
                  icon: Iconsax.maximize_1,
                  label: tr(
                    context,
                    _isFullscreen
                        ? 'player.exitFullscreen'
                        : 'player.fullscreen',
                  ),
                  onPressed: _toggleFullscreen,
                  // No collapse glyph exists in Iconsax — the orange
                  // selected state marks "fullscreen is on".
                  selected: _isFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedButton() {
    return FocusableCard(
      borderRadius: 999,
      child: PopupMenuButton<double>(
        initialValue: _speed,
        tooltip: tr(context, 'player.playbackSpeed'),
        onSelected: _setSpeed,
        color: const Color(0xFF1C1C22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
        ),
        itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            .map(
              (speed) => PopupMenuItem<double>(
                value: speed,
                child: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: speed == _speed
                        ? AppColors.brand
                        : Colors.white,
                    fontWeight: speed == _speed
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            )
            .toList(),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            '${_speed}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final message = tr(context, _error ?? 'player.videoFailed');
    final canOpenBrowser = _source.browserUrl != null;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.warning_2,
              size: 32,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'common.error'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildErrorAction(
                label: tr(context, 'common.retry'),
                icon: Iconsax.refresh,
                onPressed: () => _loadEpisode(_episodeIndex),
              ),
              if (canOpenBrowser) ...[
                const SizedBox(width: 12),
                _buildErrorAction(
                  label: tr(context, 'player.openInBrowser'),
                  icon: Iconsax.export_1,
                  onPressed: _openInBrowser,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FocusableCard(
      onPressed: onPressed,
      borderRadius: 999,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppColors.glowShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpNextCard() {
    final nextIndex = nextEpisodeIndex(_episodes.length, _episodeIndex);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tr(context, 'player.upNext'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.brandSoft,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
            if (nextIndex != null) ...[
              Text(
                trParams(context, 'player.episode', {
                  'number': episodeNumber(
                    _episodes[nextIndex],
                    fallback: nextIndex + 1,
                  ).toString(),
                }),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              if (episodeTitle(_episodes[nextIndex]).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  episodeTitle(_episodes[nextIndex]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
              const SizedBox(height: 20),
              _buildErrorAction(
                label: tr(context, 'common.play'),
                icon: Iconsax.play_copy,
                onPressed: () => _playEpisode(nextIndex),
              ),
            ] else ...[
              Text(
                tr(context, 'player.noMoreEpisodes'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 20),
              _buildErrorAction(
                label: tr(context, 'player.replay'),
                icon: Iconsax.refresh,
                onPressed: () async {
                  await _seekTo(Duration.zero);
                  setState(() => _ended = false);
                  await _togglePlay();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpNextChip() {
    final nextIndex = nextEpisodeIndex(_episodes.length, _episodeIndex);
    if (nextIndex == null) return const SizedBox.shrink();
    return Positioned(
      right: 12,
      bottom: 96,
      child: FocusableCard(
        onPressed: () => _playEpisode(nextIndex),
        borderRadius: 12,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE61C1C22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Iconsax.play_copy, size: 16, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(
                '${tr(context, 'player.upNext')}: '
                '${trParams(context, 'player.episode', {
                  'number': episodeNumber(
                    _episodes[nextIndex],
                    fallback: nextIndex + 1,
                  ).toString(),
                })}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeList() {
    final palette = context.palette;
    return Container(
      color: palette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr(context, 'player.episodes'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _episodes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final episode = _episodes[index];
                final isCurrent = index == _episodeIndex;
                final number =
                    episodeNumber(episode, fallback: index + 1);
                final durationSeconds = episodeDurationSeconds(episode);
                return FocusableCard(
                  onPressed: () => _playEpisode(index),
                  borderRadius: AppColors.radiusM,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.brand.withValues(alpha: 0.12)
                          : palette.card,
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusM),
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.brand
                            : palette.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: isCurrent
                                ? AppColors.primaryGradient
                                : null,
                            color: isCurrent
                                ? null
                                : palette.bg,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            isCurrent
                                ? Iconsax.pause_copy
                                : Iconsax.play_copy,
                            size: 18,
                            color: isCurrent
                                ? Colors.white
                                : palette.text,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trParams(context, 'player.episode', {
                                  'number': number.toString(),
                                }),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: isCurrent
                                          ? AppColors.brand
                                          : palette.text,
                                    ),
                              ),
                              if (episodeTitle(episode).isNotEmpty)
                                Text(
                                  episodeTitle(episode),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (durationSeconds > 0)
                          Text(
                            Formatters.duration(durationSeconds),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall,
                          ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Text(
                            tr(context, 'player.nowPlaying'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.brand),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
