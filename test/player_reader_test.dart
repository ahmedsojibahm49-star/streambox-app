import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/screens/player/player_logic.dart';
import 'package:streambox/screens/reader/reader_logic.dart';
import 'package:streambox/services/library_service.dart';

/// Player + reader unit tests. The video plugins (video_player,
/// youtube_player_flutter) cannot run headless, so everything under test
/// here is pure logic: source selection, navigation bounds, seek/resume
/// math, and progress persistence through the real [LibraryService] over
/// throwaway Hive boxes.
void main() {
  // -- Source-type selection -------------------------------------------------

  group('resolvePlaybackSource', () {
    test('youtubeId selects the YouTube player', () {
      final source = resolvePlaybackSource({
        'number': 1,
        'title': 'Pilot',
        'youtubeId': 'dQw4w9WgXcQ',
      });
      expect(source.type, PlaybackSourceType.youtube);
      expect(source.youtubeId, 'dQw4w9WgXcQ');
      expect(source.videoUrl, isNull);
      expect(source.hasSource, isTrue);
      expect(
        source.browserUrl,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('videoUrl selects the direct player', () {
      final source = resolvePlaybackSource({
        'number': 1,
        'videoUrl': 'https://example.com/ep1.mp4',
      });
      expect(source.type, PlaybackSourceType.direct);
      expect(source.videoUrl, 'https://example.com/ep1.mp4');
      expect(source.youtubeId, isNull);
      expect(source.hasSource, isTrue);
      expect(source.browserUrl, 'https://example.com/ep1.mp4');
    });

    test('neither source means no source (error state, never a crash)', () {
      final source = resolvePlaybackSource({'number': 1, 'title': 'Pilot'});
      expect(source.type, PlaybackSourceType.none);
      expect(source.hasSource, isFalse);
      expect(source.browserUrl, isNull);
    });

    test('blank strings count as missing', () {
      final source = resolvePlaybackSource({
        'youtubeId': '   ',
        'videoUrl': '',
      });
      expect(source.type, PlaybackSourceType.none);
    });

    test('youtubeId wins when the episode has both', () {
      final source = resolvePlaybackSource({
        'youtubeId': 'abc123',
        'videoUrl': 'https://example.com/ep1.mp4',
      });
      expect(source.type, PlaybackSourceType.youtube);
    });

    test('source hint overrides the default priority when available', () {
      final direct = resolvePlaybackSource(
        {
          'youtubeId': 'abc123',
          'videoUrl': 'https://example.com/ep1.mp4',
        },
        sourceHint: 'direct',
      );
      expect(direct.type, PlaybackSourceType.direct);

      final youtube = resolvePlaybackSource(
        {
          'youtubeId': 'abc123',
          'videoUrl': 'https://example.com/ep1.mp4',
        },
        sourceHint: 'youtube',
      );
      expect(youtube.type, PlaybackSourceType.youtube);
    });

    test('source hint is ignored when the episode lacks that source', () {
      final source = resolvePlaybackSource(
        {'videoUrl': 'https://example.com/ep1.mp4'},
        sourceHint: 'youtube',
      );
      expect(source.type, PlaybackSourceType.direct);
    });

    test('youtubeWatchUrl builds the browser fallback URL', () {
      expect(
        youtubeWatchUrl('abc123'),
        'https://www.youtube.com/watch?v=abc123',
      );
    });
  });

  // -- Episode navigation ------------------------------------------------------

  group('episode navigation', () {
    final episodes = [
      {'number': 1, 'title': 'Pilot'},
      {'number': 2, 'title': 'Second'},
      {'number': 5, 'title': 'Fifth'},
    ];

    test('episodeIndexFor finds the episode by number', () {
      expect(episodeIndexFor(episodes, 2), 1);
      expect(episodeIndexFor(episodes, 5), 2);
    });

    test('episodeIndexFor falls back to the first episode', () {
      expect(episodeIndexFor(episodes, null), 0);
      expect(episodeIndexFor(episodes, 99), 0);
      expect(episodeIndexFor([], 1), 0);
    });

    test('next/previous episode bounds', () {
      expect(nextEpisodeIndex(3, 0), 1);
      expect(nextEpisodeIndex(3, 1), 2);
      expect(nextEpisodeIndex(3, 2), isNull);
      expect(previousEpisodeIndex(2), 1);
      expect(previousEpisodeIndex(1), 0);
      expect(previousEpisodeIndex(0), isNull);
    });

    test('episodeNumber falls back to list position + 1', () {
      expect(episodeNumber({}, fallback: 3), 3);
      expect(episodeNumber({'number': '7'}), 7);
      expect(episodeNumber({'number': 0}, fallback: 2), 2);
    });

    test('episodeDurationSeconds reads the declared runtime', () {
      expect(episodeDurationSeconds({'durationSeconds': 1420}), 1420);
      expect(episodeDurationSeconds({}), 0);
      expect(episodeDurationSeconds({'durationSeconds': -5}), 0);
    });
  });

  // -- Chapter navigation --------------------------------------------------------

  group('chapter navigation', () {
    final chapters = [
      {
        'number': 1,
        'title': 'Begin',
        'pageUrls': ['https://example.com/p1.jpg'],
      },
      {
        'number': 2,
        'title': 'Next',
        'pageUrls': [
          'https://example.com/p2.jpg',
          'not-a-url',
          'ftp://example.com/p3.jpg',
        ],
      },
    ];

    test('chapterIndexFor finds the chapter by number', () {
      expect(chapterIndexFor(chapters, 2), 1);
    });

    test('chapterIndexFor falls back to the first chapter', () {
      expect(chapterIndexFor(chapters, null), 0);
      expect(chapterIndexFor(chapters, 99), 0);
      expect(chapterIndexFor([], 1), 0);
    });

    test('next/previous chapter bounds', () {
      expect(nextChapterIndex(2, 0), 1);
      expect(nextChapterIndex(2, 1), isNull);
      expect(previousChapterIndex(1), 0);
      expect(previousChapterIndex(0), isNull);
    });

    test('chapterPageUrls keeps only http(s) URLs', () {
      expect(chapterPageUrls(chapters[1]), ['https://example.com/p2.jpg']);
      expect(chapterPageUrls({}), isEmpty);
    });

    test('clampPage and readingProgress', () {
      expect(clampPage(0, 10), 0);
      expect(clampPage(9, 10), 9);
      expect(clampPage(99, 10), 9);
      expect(clampPage(-1, 10), 0);
      expect(clampPage(0, 0), 0);
      expect(readingProgress(0, 10), 0.1);
      expect(readingProgress(9, 10), 1.0);
      expect(readingProgress(0, 0), 0);
    });

    test('pageFromScrollOffset maps scroll to a page', () {
      expect(pageFromScrollOffset(0, 800, 10), 0);
      expect(pageFromScrollOffset(850, 800, 10), 1);
      expect(pageFromScrollOffset(99999, 800, 10), 9);
      expect(pageFromScrollOffset(100, 0, 10), 0);
    });

    test('parseReaderMode', () {
      expect(parseReaderMode(null), ReaderMode.page);
      expect(parseReaderMode('page'), ReaderMode.page);
      expect(parseReaderMode('vertical'), ReaderMode.vertical);
      expect(parseReaderMode('scroll'), ReaderMode.vertical);
      expect(parseReaderMode('VERTICAL'), ReaderMode.vertical);
      expect(parseReaderMode('bogus'), ReaderMode.page);
    });
  });

  // -- Seek / resume / progress math ---------------------------------------------

  group('seek and resume math', () {
    test('clampSeek stays inside the video', () {
      const duration = Duration(minutes: 10);
      expect(clampSeek(const Duration(seconds: 30), duration),
          const Duration(seconds: 30));
      expect(clampSeek(const Duration(seconds: -5), duration), Duration.zero);
      expect(clampSeek(const Duration(minutes: 11), duration), duration);
      expect(clampSeek(const Duration(seconds: 5), Duration.zero),
          Duration.zero);
    });

    test('seekBy skips ±10s and clamps at both ends', () {
      const duration = Duration(minutes: 10);
      expect(seekBy(const Duration(seconds: 100), duration, 10),
          const Duration(seconds: 110));
      expect(seekBy(const Duration(seconds: 100), duration, -10),
          const Duration(seconds: 90));
      expect(seekBy(const Duration(seconds: 5), duration, -10),
          Duration.zero);
      expect(seekBy(const Duration(seconds: 595), duration, 10), duration);
    });

    test('resumePositionSeconds returns 0 when there is nothing to resume', () {
      expect(resumePositionSeconds(savedSeconds: 0, durationSeconds: 600),
          0);
      expect(resumePositionSeconds(savedSeconds: -5, durationSeconds: 600),
          0);
      // At/past the end — start over.
      expect(resumePositionSeconds(savedSeconds: 600, durationSeconds: 600),
          0);
      expect(resumePositionSeconds(savedSeconds: 700, durationSeconds: 600),
          0);
      // Within the last 10 seconds — the episode is effectively finished.
      expect(resumePositionSeconds(savedSeconds: 595, durationSeconds: 600),
          0);
      expect(resumePositionSeconds(savedSeconds: 590, durationSeconds: 600),
          0);
    });

    test('resumePositionSeconds passes a mid-video position through', () {
      expect(resumePositionSeconds(savedSeconds: 300, durationSeconds: 600),
          300);
      // Unknown duration: trust the saved position.
      expect(resumePositionSeconds(savedSeconds: 300, durationSeconds: 0),
          300);
    });

    test('progressFraction clamps to 0..1', () {
      expect(progressFraction(0, 600), 0);
      expect(progressFraction(300, 600), 0.5);
      expect(progressFraction(600, 600), 1);
      expect(progressFraction(700, 600), 1);
      expect(progressFraction(10, 0), 0);
    });

    test('shouldShowUpNext only near the end with a next episode', () {
      expect(
        shouldShowUpNext(
          position: const Duration(seconds: 100),
          duration: const Duration(seconds: 600),
          hasNext: true,
        ),
        isFalse,
      );
      expect(
        shouldShowUpNext(
          position: const Duration(seconds: 590),
          duration: const Duration(seconds: 600),
          hasNext: true,
        ),
        isTrue,
      );
      expect(
        shouldShowUpNext(
          position: const Duration(seconds: 600),
          duration: const Duration(seconds: 600),
          hasNext: true,
        ),
        isTrue,
      );
      expect(
        shouldShowUpNext(
          position: const Duration(seconds: 590),
          duration: const Duration(seconds: 600),
          hasNext: false,
        ),
        isFalse,
      );
    });

    test('parseBoxKey splits provider and item ids', () {
      final parts = parseBoxKey('sample::last-horizon');
      expect(parts?.providerId, 'sample');
      expect(parts?.itemId, 'last-horizon');
      expect(parseBoxKey('no-separator'), isNull);
      expect(parseBoxKey('::'), isNull);
      expect(parseBoxKey('a::'), isNull);
    });
  });

  // -- Progress persistence (real LibraryService + throwaway Hive boxes) --------

  group('progress saving via LibraryService', () {
    late Directory tempDir;
    late Box<LibraryEntry> libraryBox;
    late Box<HistoryEntry> historyBox;
    late LibraryService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('streambox-player-test');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(LibraryEntryAdapter().typeId)) {
        Hive.registerAdapter(LibraryEntryAdapter());
      }
      if (!Hive.isAdapterRegistered(HistoryEntryAdapter().typeId)) {
        Hive.registerAdapter(HistoryEntryAdapter());
      }
      libraryBox = await Hive.openBox<LibraryEntry>('library');
      historyBox = await Hive.openBox<HistoryEntry>('history');
      service = LibraryService(libraryBox, historyBox);
    });

    tearDown(() async {
      await libraryBox.close();
      await historyBox.close();
      await Hive.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('recordProgress writes a history entry with the right position',
        () async {
      await service.recordProgress(
        itemId: 'last-horizon',
        providerId: 'sample',
        episodeOrChapter: 3,
        positionSeconds: 742,
      );

      final entry = service.progressFor(
        itemId: 'last-horizon',
        providerId: 'sample',
      );
      expect(entry, isNotNull);
      expect(entry!.episodeOrChapter, 3);
      expect(entry.positionSeconds, 742);
      expect(entry.page, 0);
      expect(entry.boxKey, 'sample::last-horizon');
    });

    test('a later record overwrites the earlier position (latest wins)',
        () async {
      await service.recordProgress(
        itemId: 'last-horizon',
        providerId: 'sample',
        episodeOrChapter: 3,
        positionSeconds: 100,
      );
      await service.recordProgress(
        itemId: 'last-horizon',
        providerId: 'sample',
        episodeOrChapter: 3,
        positionSeconds: 742,
      );

      final entry = service.progressFor(
        itemId: 'last-horizon',
        providerId: 'sample',
      );
      expect(entry!.positionSeconds, 742);
      expect(historyBox.length, 1);
    });

    test('reader progress records chapter + page, no video position',
        () async {
      await service.recordProgress(
        itemId: 'paper-moons',
        providerId: 'sample',
        episodeOrChapter: 12,
        page: 7,
      );

      final entry = service.progressFor(
        itemId: 'paper-moons',
        providerId: 'sample',
      );
      expect(entry, isNotNull);
      expect(entry!.episodeOrChapter, 12);
      expect(entry.page, 7);
      expect(entry.positionSeconds, 0);
    });

    test('continueWatching surfaces entries with real progress', () async {
      await service.recordProgress(
        itemId: 'a',
        providerId: 'sample',
        episodeOrChapter: 1,
        positionSeconds: 120,
      );
      await service.recordProgress(
        itemId: 'b',
        providerId: 'sample',
        episodeOrChapter: 1,
        page: 4,
      );
      await service.recordProgress(
        itemId: 'c',
        providerId: 'sample',
        episodeOrChapter: 1,
      );

      final continuing = service.continueWatching();
      expect(continuing.map((e) => e.itemId), containsAll(['a', 'b']));
      expect(continuing.map((e) => e.itemId), isNot(contains('c')));
    });

    test('progressFor returns null for an item never opened', () {
      expect(
        service.progressFor(itemId: 'never-opened', providerId: 'sample'),
        isNull,
      );
    });
  });
}
