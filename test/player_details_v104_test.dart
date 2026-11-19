import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:streambox/i18n/i18n.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/providers/catalog_providers.dart';
import 'package:streambox/screens/details_screen.dart';
import 'package:streambox/screens/player/player_screen.dart';
import 'package:streambox/services/library_service.dart';
import 'package:streambox/services/storage.dart';
import 'package:streambox/theme/app_theme.dart';
import 'package:streambox/widgets/pause_bars.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// v1.0.4 regression tests for the player + details fix pass:
///
/// 1. [PauseBars] draws two tall bars with a gap (never a glyph that can
///    read as "00").
/// 2. Details at 360px: the action button says just "Resume", the episode
///    number lives in the caption underneath, and nothing clips or
///    overflows anywhere on the page.
/// 3. Player: a direct-video init failure shows the visible error state
///    (not a silent black 0:00 screen), and the episode row does not claim
///    "Now playing" when nothing is playing.
///
/// Hermetic: the catalog/history providers are overridden with fixed data,
/// Hive runs on a throwaway temp dir (same pattern as audit_fixes_test),
/// and the video platform is replaced by [_ThrowingVideoPlayerPlatform]
/// for the player test so `initialize()` fails deterministically.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-v104-test');
    Hive.init(tempDir.path);
    await initStorage();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
  });

  group('PauseBars', () {
    testWidgets('renders two tall bars with a gap, never a glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PauseBars(height: 18))),
        ),
      );

      // No Icon anywhere — the glyph is what read as "00".
      expect(find.byType(Icon), findsNothing);
      final bars = find.descendant(
        of: find.byType(PauseBars),
        matching: find.byType(Container),
      );
      expect(bars, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(bars.at(i));
        expect(size.height, 18);
        // Tall and narrow — a square-ish bar is what read as "00".
        expect(size.width, lessThan(size.height / 2));
      }
      // A real gap between the bars (second bar starts after the first
      // bar ends).
      expect(
        tester.getTopLeft(bars.at(1)).dx,
        greaterThan(tester.getBottomRight(bars.at(0)).dx),
      );
    });
  });

  group('DetailsScreen at 360px', () {
    testWidgets(
      'Resume label, caption carries the episode, nothing overflows',
      (tester) async {
        _setNarrowSurface(tester);
        final item = _testItem();
        await _pumpDetails(tester, item, history: [_progressEntry()]);

        expect(find.text('Resume'), findsOneWidget);
        expect(find.textContaining('Resume episode'), findsNothing);
        expect(find.textContaining('Resume chapter'), findsNothing);
        // The episode number moved to the caption underneath the button.
        expect(find.text('Episode 3 · 12:34'), findsOneWidget);

        // Scroll to the episodes: the resume target row shows its saved
        // position ("12:34 / 24:00").
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.text('12:34 / 24:00'), findsOneWidget);

        // Scroll through the rest of the page — any overflow anywhere
        // (action row, chips, episode rows, More Like This) fails here.
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('without progress the button still says Watch now', (
      tester,
    ) async {
      _setNarrowSurface(tester);
      await _pumpDetails(tester, _testItem());

      expect(find.text('Watch now'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PlayerScreen error state', () {
    testWidgets('direct init failure shows the error overlay, not 0:00', (
      tester,
    ) async {
      _setNarrowSurface(tester);
      // Install the throwing platform so initialize() fails
      // deterministically (see [_ThrowingVideoPlayerPlatform]); restore
      // the real platform afterwards so other test files are unaffected.
      final previousPlatform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _ThrowingVideoPlayerPlatform();
      addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
      final item = _testItem();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [itemByIdProvider.overrideWith((ref, id) => item)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: PlayerScreen(itemId: item.boxKey),
          ),
        ),
      );
      // pumpAndSettle NEVER completes here: the player runs a 10s periodic
      // progress timer, so FakeAsync always has a pending timer. Pump
      // until the error overlay appears instead (bounded). The error
      // path takes ~2s of fake time (the dispose timeout after the
      // failed create); 15s of pumping is ample.
      final errorText =
          find.text(trForLocale(const Locale('en'), 'player.videoFailed'));
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (errorText.evaluate().isNotEmpty) break;
      }

      // initialize() throws on the throwing platform — the player must
      // surface that as the error state with Retry, and the spinner must
      // be gone.
      expect(errorText, findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Nothing is actually playing, so the episode row must not claim
      // "Now playing" and must not show pause bars.
      expect(find.text('Now playing'), findsNothing);
      expect(find.byType(PauseBars), findsNothing);
      // The error overlay must fit the ~202px-tall portrait video area.
      expect(tester.takeException(), isNull);

      // Dispose the player inside runAsync: State.dispose() saves
      // progress to Hive (real file I/O). If that write starts inside the
      // FakeAsync test zone its completion callback is stranded in the
      // dead zone after the test ends, and Hive.close() in tearDownAll
      // hangs forever waiting for it.
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  });
}

/// Video platform that fails every player creation — simulates the
/// broken-plugin-layer device where `initialize()` can never succeed.
///
/// A fake platform (not "no plugin registered"): with no plugin at all
/// the Pigeon channel never replies, so `initialize()` hangs until the
/// 20s timeout AND the follow-up `dispose()` hangs forever (video_player
/// 2.14's dispose awaits an internal completer that only completes when
/// create returns). The fake throws synchronously instead, so the test
/// exercises the error path deterministically.
class _ThrowingVideoPlayerPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements VideoPlayerPlatform {
  @override
  Future<int?> create(DataSource dataSource) async {
    throw StateError('simulated video init failure');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    throw StateError('simulated video init failure');
  }

  @override
  Future<void> dispose(int playerId) async {}
}

/// History state fixed to [entries] (avoids Hive reads in the notifier).
class _FixedHistory extends HistoryNotifier {
  _FixedHistory(this._entries);

  final List<HistoryEntry> _entries;

  @override
  List<HistoryEntry> build() => _entries;
}

void _setNarrowSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ProviderItem _testItem() {
  return ProviderItem(
    id: 'show-1',
    providerId: 'sample',
    type: ContentType.anime,
    title: 'The Last Horizon: A Very Long Title That Must Ellipsize Cleanly',
    year: 2026,
    rating: 8.7,
    genres: const ['Action', 'Sci-Fi', 'Drama'],
    overview:
        'A test overview that is long enough to wrap over several lines '
        'so the details page layout gets a realistic workout.',
    status: 'ongoing',
    episodesJson: jsonEncode([
      {
        'number': 1,
        'title': 'Pilot',
        'videoUrl': 'https://example.com/ep1.mp4',
        'durationSeconds': 1440,
      },
      {
        'number': 2,
        'title': 'Second Episode',
        'videoUrl': 'https://example.com/ep2.mp4',
        'durationSeconds': 1440,
      },
      {
        'number': 3,
        'title': 'Third Episode With A Long Title',
        'videoUrl': 'https://example.com/ep3.mp4',
        'durationSeconds': 1440,
      },
    ]),
  );
}

HistoryEntry _progressEntry() => HistoryEntry(
  itemId: 'show-1',
  providerId: 'sample',
  episodeOrChapter: 3,
  positionSeconds: 754,
  updatedAt: DateTime.utc(2026, 11, 19),
);

Future<void> _pumpDetails(
  WidgetTester tester,
  ProviderItem item, {
  List<HistoryEntry> history = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        itemByIdProvider.overrideWith((ref, id) => item),
        historyProvider.overrideWith(() => _FixedHistory(history)),
        isInMyListProvider.overrideWith((ref, key) => false),
        isFavoriteProvider.overrideWith((ref, key) => false),
        allEnabledItemsProvider.overrideWith((ref) => [item]),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: DetailsScreen(itemId: item.boxKey),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
