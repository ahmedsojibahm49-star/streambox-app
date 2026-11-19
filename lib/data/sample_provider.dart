import 'dart:convert';

// NOTE: imports provider_item.dart directly (not the models barrel) so the
// sample-data generator (`dart tool/generate_sample_repo.dart`) can run on
// plain Dart — the barrel pulls in app_settings.dart, which needs Flutter.
import '../models/provider_item.dart';

/// Built-in sample provider — the single source of truth for the sample
/// catalog. ALL titles are fictional; no real anime/movie/manga names and no
/// real site names anywhere.
///
/// The same content ships as JSON in `assets/sample-repo.json` (bundled with
/// the app, loaded by the "Load example" button) and `sample-repo.json` at
/// the project root (for hosting). Both JSON files are GENERATED from this
/// file — regenerate with `dart tool/generate_sample_repo.dart`, never edit
/// them by hand.
///
/// Posters/backdrops are the 15 bundled artwork assets
/// (`assets/artwork/*.jpg`). Episode videos are Google's public sample
/// videos (Big Buck Bunny, Elephants Dream, Sintel, Tears of Steel —
/// standard public test videos). Chapter pages are seeded picsum.photos
/// images. `youtubeId` is intentionally left null everywhere.

const String sampleRepoId = 'sample';
const String sampleRepoName = 'Sample Catalog';
const String sampleRepoSourceUrl = 'asset://sample-repo.json';
const int sampleRepoVersion = 1;

/// Google's public sample videos (legal test videos, used for playback).
const String _videoBbb =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
const String _videoElephants =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4';
const String _videoSintel =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4';
const String _videoTears =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4';

Map<String, dynamic> _episode(
  int number,
  String title,
  String videoUrl, [
  int durationSeconds = 1420,
]) =>
    {
      'number': number,
      'title': title,
      'videoUrl': videoUrl,
      'durationSeconds': durationSeconds,
    };

Map<String, dynamic> _chapter(int number, String title, String seed) => {
      'number': number,
      'title': title,
      'pageUrls': [
        for (var p = 1; p <= 3; p++)
          'https://picsum.photos/seed/$seed-$p/800/1200',
      ],
    };

/// The 24 sample items as repo-JSON maps (same shape as the documented
/// repo format — see docs/provider-format.md).
List<Map<String, dynamic>> sampleRepoItemsJson() => [
      // -- Anime (7) -------------------------------------------------------
      {
        'id': 'last-horizon',
        'type': 'anime',
        'title': 'Last Horizon',
        'posterUrl': 'assets/artwork/last-horizon-poster.jpg',
        'backdropUrl': 'assets/artwork/hero-last-horizon.jpg',
        'year': 2025,
        'rating': 8.9,
        'genres': ['Sci-Fi', 'Adventure'],
        'overview':
            'A cartographer on the last survey ship maps a sea that redraws itself every night — and finds an island that should not exist.',
        'status': 'ongoing',
        'episodes': [
          _episode(1, 'The Sea That Moves', _videoBbb),
          _episode(2, 'Cartography of Ghosts', _videoSintel),
          _episode(3, 'The Thirteenth Island', _videoTears),
        ],
      },
      {
        'id': 'neon-frontier',
        'type': 'anime',
        'title': 'Neon Frontier',
        'posterUrl': 'assets/artwork/neon-frontier-poster.jpg',
        'backdropUrl': 'assets/artwork/neon-frontier-skyline-wide.jpg',
        'year': 2024,
        'rating': 8.7,
        'genres': ['Cyberpunk', 'Action'],
        'overview':
            'In a city where memories are currency, a courier who cannot forget takes one last job across the neon divide.',
        'status': 'ongoing',
        'episodes': [
          _episode(1, 'Memory Is Currency', _videoSintel),
          _episode(2, 'The Courier', _videoBbb),
          _episode(3, 'Across the Divide', _videoElephants),
        ],
      },
      {
        'id': 'echoes-tomorrow',
        'type': 'anime',
        'title': 'Echoes of Tomorrow',
        'posterUrl': 'assets/artwork/poster-echoes-tomorrow.jpg',
        'backdropUrl': 'assets/artwork/echoes-tomorrow-wide.jpg',
        'year': 2025,
        'rating': 9.1,
        'genres': ['Drama', 'Sci-Fi'],
        'overview':
            'Every morning, Mira wakes to voicemails from a future version of herself. Today, the messages stop.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Voicemails from Tomorrow', _videoElephants),
          _episode(2, 'The Silent Morning', _videoTears),
          _episode(3, 'Answer the Future', _videoSintel),
        ],
      },
      {
        'id': 'foxglove-academy',
        'type': 'anime',
        'title': 'Foxglove Academy',
        'posterUrl': 'assets/artwork/paper-moons-poster.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2024,
        'rating': 8.2,
        'genres': ['School', 'Fantasy'],
        'overview':
            'A school for young hedge-witches where the final exam is keeping the school itself from wandering off.',
        'status': 'ongoing',
        'episodes': [
          _episode(1, 'Orientation Day', _videoTears),
          _episode(2, 'The Wandering Library', _videoBbb),
          _episode(3, 'Final Exam', _videoSintel),
        ],
      },
      {
        'id': 'hollow-signal',
        'type': 'anime',
        'title': 'Hollow Signal',
        'posterUrl': 'assets/artwork/glass-detective-poster.jpg',
        'backdropUrl': 'assets/artwork/echoes-tomorrow-wide.jpg',
        'year': 2026,
        'rating': 8.5,
        'genres': ['Mystery', 'Thriller'],
        'overview':
            'A late-night radio host starts receiving calls from a station that went off the air forty years ago.',
        'status': 'ongoing',
        'episodes': [
          _episode(1, 'Frequency 87.4', _videoBbb),
          _episode(2, 'The Caller', _videoElephants),
          _episode(3, 'Dead Air', _videoTears),
        ],
      },
      {
        'id': 'static-bloom',
        'type': 'anime',
        'title': 'Static Bloom',
        'posterUrl': 'assets/artwork/silent-tide-poster.jpg',
        'backdropUrl': 'assets/artwork/neon-frontier-skyline-wide.jpg',
        'year': 2023,
        'rating': 7.9,
        'genres': ['Romance', 'Slice of Life'],
        'overview':
            'Two rival florists share one tiny shop, one broken radio, and a summer neither of them planned.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'One Shop, Two Florists', _videoSintel),
          _episode(2, 'The Broken Radio', _videoTears),
          _episode(3, 'Summer Blooms', _videoBbb),
        ],
      },
      {
        'id': 'ninth-lantern',
        'type': 'anime',
        'title': 'The Ninth Lantern',
        'posterUrl': 'assets/artwork/solar-winds-poster.jpg',
        'backdropUrl': 'assets/artwork/hero-last-horizon.jpg',
        'year': 2025,
        'rating': 8.8,
        'genres': ['Fantasy', 'Adventure'],
        'overview':
            'Eight lanterns light the mountain pass. A young keeper must relight the ninth — the one nobody admits exists.',
        'status': 'ongoing',
        'episodes': [
          _episode(1, 'Keeper of the Pass', _videoElephants),
          _episode(2, 'The Lantern Nobody Sees', _videoSintel),
          _episode(3, 'Light the Ninth', _videoBbb),
        ],
      },
      // -- Movies (7) ------------------------------------------------------
      {
        'id': 'midnight-city',
        'type': 'movie',
        'title': 'Midnight City',
        'posterUrl': 'assets/artwork/poster-midnight-city.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2025,
        'rating': 8.4,
        'genres': ['Noir', 'Crime'],
        'overview':
            'One night, one taxi, and a driver who knows every secret the city tries to keep after midnight.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoBbb, 6240),
        ],
      },
      {
        'id': 'glass-detective',
        'type': 'movie',
        'title': 'Glass Detective',
        'posterUrl': 'assets/artwork/glass-detective-poster.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2024,
        'rating': 8.6,
        'genres': ['Mystery', 'Thriller'],
        'overview':
            'A detective who reads crimes from broken glass takes a case where every mirror in the house is intact — except one.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoSintel, 7020),
        ],
      },
      {
        'id': 'northern-lights',
        'type': 'movie',
        'title': 'Northern Lights',
        'posterUrl': 'assets/artwork/northern-lights-poster.jpg',
        'backdropUrl': 'assets/artwork/echoes-tomorrow-wide.jpg',
        'year': 2026,
        'rating': 9.0,
        'genres': ['Drama', 'Romance'],
        'overview':
            'Two strangers chase the aurora across a frozen north, carrying letters neither of them wrote.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoElephants, 6480),
        ],
      },
      {
        'id': 'solar-winds',
        'type': 'movie',
        'title': 'Solar Winds',
        'posterUrl': 'assets/artwork/solar-winds-poster.jpg',
        'backdropUrl': 'assets/artwork/neon-frontier-skyline-wide.jpg',
        'year': 2023,
        'rating': 7.8,
        'genres': ['Sci-Fi', 'Adventure'],
        'overview':
            'A solar-sail race around the sun, where the fastest ship is crewed by the slowest family in the fleet.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoTears, 5940),
        ],
      },
      {
        'id': 'crimson-harbor',
        'type': 'movie',
        'title': 'Crimson Harbor',
        'posterUrl': 'assets/artwork/wild-ember-poster.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2025,
        'rating': 8.1,
        'genres': ['Drama', 'Mystery'],
        'overview':
            'A harbor town paints its boats crimson once a year. This year, one boat returns that never left.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoBbb, 6660),
        ],
      },
      {
        'id': 'velvet-thunder',
        'type': 'movie',
        'title': 'Velvet Thunder',
        'posterUrl': 'assets/artwork/neon-frontier-poster.jpg',
        'backdropUrl': 'assets/artwork/player-last-horizon.jpg',
        'year': 2024,
        'rating': 7.6,
        'genres': ['Action', 'Music'],
        'overview':
            'A retired stunt drummer is pulled back for one last heist — timed to a song only she can hear.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoSintel, 5760),
        ],
      },
      {
        'id': 'moonlit-foundry',
        'type': 'movie',
        'title': 'Moonlit Foundry',
        'posterUrl': 'assets/artwork/last-horizon-poster.jpg',
        'backdropUrl': 'assets/artwork/hero-last-horizon.jpg',
        'year': 2026,
        'rating': 8.3,
        'genres': ['Fantasy', 'Family'],
        'overview':
            'A blacksmith who forges tools from moonlight must make one last key before the moon goes dark for a hundred years.',
        'status': 'completed',
        'episodes': [
          _episode(1, 'Full movie', _videoElephants, 6120),
        ],
      },
      // -- Manga (5) -------------------------------------------------------
      {
        'id': 'paper-moons',
        'type': 'manga',
        'title': 'Paper Moons',
        'posterUrl': 'assets/artwork/paper-moons-poster.jpg',
        'backdropUrl': 'assets/artwork/echoes-tomorrow-wide.jpg',
        'year': 2022,
        'rating': 8.7,
        'genres': ['Romance', 'Drama'],
        'overview':
            'A paper artist folds a moon for the girl across the street every month — and one month, she folds one back.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The First Fold', 'paper-moons-1'),
          _chapter(2, 'Waxing', 'paper-moons-2'),
          _chapter(3, 'A Moon in Return', 'paper-moons-3'),
        ],
      },
      {
        'id': 'iron-blossom',
        'type': 'manga',
        'title': 'Iron Blossom',
        'posterUrl': 'assets/artwork/wild-ember-poster.jpg',
        'backdropUrl': 'assets/artwork/neon-frontier-skyline-wide.jpg',
        'year': 2023,
        'rating': 8.9,
        'genres': ['Action', 'Samurai'],
        'overview':
            'A retired swordsmith picks up the blade one last time to protect the apprentice who surpassed her.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Retired Blade', 'iron-blossom-1'),
          _chapter(2, 'The Apprentice', 'iron-blossom-2'),
          _chapter(3, 'One Last Cut', 'iron-blossom-3'),
        ],
      },
      {
        'id': 'cartographers-daughter',
        'type': 'manga',
        'title': "The Cartographer's Daughter",
        'posterUrl': 'assets/artwork/northern-lights-poster.jpg',
        'backdropUrl': 'assets/artwork/hero-last-horizon.jpg',
        'year': 2024,
        'rating': 9.2,
        'genres': ['Adventure', 'Fantasy'],
        'overview':
            'Inheriting her father\'s unfinished atlas, a girl sets out to map the blank quarter — where the map itself fights back.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Unfinished Atlas', 'cartographer-1'),
          _chapter(2, 'The Blank Quarter', 'cartographer-2'),
          _chapter(3, 'The Map Fights Back', 'cartographer-3'),
        ],
      },
      {
        'id': 'rust-stardust',
        'type': 'manga',
        'title': 'Rust & Stardust',
        'posterUrl': 'assets/artwork/solar-winds-poster.jpg',
        'backdropUrl': 'assets/artwork/player-last-horizon.jpg',
        'year': 2021,
        'rating': 8.0,
        'genres': ['Sci-Fi', 'Mecha'],
        'overview':
            'A junkyard mechanic rebuilds a fallen star-soldier from scrap — and the soldier remembers the war differently.',
        'status': 'completed',
        'chapters': [
          _chapter(1, 'Scrapyard', 'rust-stardust-1'),
          _chapter(2, 'The Fallen Soldier', 'rust-stardust-2'),
          _chapter(3, 'A Different War', 'rust-stardust-3'),
        ],
      },
      {
        'id': 'emberline-express',
        'type': 'manga',
        'title': 'Emberline Express',
        'posterUrl': 'assets/artwork/poster-midnight-city.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2025,
        'rating': 8.4,
        'genres': ['Mystery', 'Supernatural'],
        'overview':
            'A night train that only stops for passengers who are already gone. Its new conductor is very much alive — for now.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Night Train', 'emberline-1'),
          _chapter(2, 'Passengers Who Are Gone', 'emberline-2'),
          _chapter(3, 'The Living Conductor', 'emberline-3'),
        ],
      },
      // -- Manhwa (5) ------------------------------------------------------
      {
        'id': 'silent-tide',
        'type': 'manhwa',
        'title': 'Silent Tide',
        'posterUrl': 'assets/artwork/silent-tide-poster.jpg',
        'backdropUrl': 'assets/artwork/echoes-tomorrow-wide.jpg',
        'year': 2023,
        'rating': 8.8,
        'genres': ['Fantasy', 'Romance'],
        'overview':
            'A tide-witch who lost her voice bargains with the sea: one song, one storm, one love she cannot speak.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Voiceless Witch', 'silent-tide-1'),
          _chapter(2, 'Bargain with the Sea', 'silent-tide-2'),
          _chapter(3, 'One Song, One Storm', 'silent-tide-3'),
        ],
      },
      {
        'id': 'wild-ember',
        'type': 'manhwa',
        'title': 'Wild Ember',
        'posterUrl': 'assets/artwork/wild-ember-poster.jpg',
        'backdropUrl': 'assets/artwork/neon-frontier-skyline-wide.jpg',
        'year': 2024,
        'rating': 8.5,
        'genres': ['Action', 'Fantasy'],
        'overview':
            'The last ember-keeper flees a kingdom that outlawed fire — carrying the only flame that can never go out.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Last Flame', 'wild-ember-1'),
          _chapter(2, 'A Kingdom Without Fire', 'wild-ember-2'),
          _chapter(3, 'The Ember That Never Dies', 'wild-ember-3'),
        ],
      },
      {
        'id': 'salted-crown',
        'type': 'manhwa',
        'title': 'The Salted Crown',
        'posterUrl': 'assets/artwork/glass-detective-poster.jpg',
        'backdropUrl': 'assets/artwork/hero-last-horizon.jpg',
        'year': 2025,
        'rating': 9.0,
        'genres': ['Drama', 'Political'],
        'overview':
            'A salt merchant inherits a drowned throne and must rule a court that drowned with it.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'The Drowned Throne', 'salted-crown-1'),
          _chapter(2, 'A Court Underwater', 'salted-crown-2'),
          _chapter(3, 'The Merchant Queen', 'salted-crown-3'),
        ],
      },
      {
        'id': 'clockwork-garden',
        'type': 'manhwa',
        'title': 'Clockwork Garden',
        'posterUrl': 'assets/artwork/poster-echoes-tomorrow.jpg',
        'backdropUrl': 'assets/artwork/player-last-horizon.jpg',
        'year': 2022,
        'rating': 8.3,
        'genres': ['Steampunk', 'Mystery'],
        'overview':
            'A gardener tends mechanical flowers that bloom only for liars — and someone in the manor is lying about a murder.',
        'status': 'completed',
        'chapters': [
          _chapter(1, 'Flowers for Liars', 'clockwork-1'),
          _chapter(2, 'The Manor', 'clockwork-2'),
          _chapter(3, 'The Last Bloom', 'clockwork-3'),
        ],
      },
      {
        'id': 'gilded-tide',
        'type': 'manhwa',
        'title': 'The Gilded Tide',
        'posterUrl': 'assets/artwork/northern-lights-poster.jpg',
        'backdropUrl': 'assets/artwork/midnight-city-wide.jpg',
        'year': 2026,
        'rating': 8.6,
        'genres': ['Adventure', 'Pirates'],
        'overview':
            'A pirate crew sails a sea of liquid gold, chasing the one island the tide refuses to return.',
        'status': 'ongoing',
        'chapters': [
          _chapter(1, 'A Sea of Gold', 'gilded-tide-1'),
          _chapter(2, 'The Island That Waits', 'gilded-tide-2'),
          _chapter(3, 'Ride the Tide', 'gilded-tide-3'),
        ],
      },
    ];

/// The full sample repo document (same shape as a hosted repo JSON file).
Map<String, dynamic> sampleRepoDocument() => {
      'name': sampleRepoName,
      'version': sampleRepoVersion,
      'items': sampleRepoItemsJson(),
    };

/// Pretty-printed sample repo JSON. Used by the "Load example" fallback and
/// by `tool/generate_sample_repo.dart` to write the JSON files.
String get sampleRepoJsonString =>
    const JsonEncoder.withIndent('  ').convert(sampleRepoDocument());

/// The sample items as [ProviderItem]s (provider `sample`).
List<ProviderItem> sampleRepoItems() =>
    sampleRepoItemsJson().map(_itemFromMap).toList(growable: false);

ProviderItem _itemFromMap(Map<String, dynamic> map) {
  final type = switch (map['type']) {
    'anime' => ContentType.anime,
    'movie' => ContentType.movie,
    'manga' => ContentType.manga,
    'manhwa' => ContentType.manhwa,
    _ => throw ArgumentError('Unknown sample type ${map['type']}'),
  };
  final episodes = map['episodes'] as List?;
  final chapters = map['chapters'] as List?;
  return ProviderItem(
    id: map['id'] as String,
    providerId: sampleRepoId,
    type: type,
    title: map['title'] as String,
    posterUrl: map['posterUrl'] as String?,
    backdropUrl: map['backdropUrl'] as String?,
    year: map['year'] as int?,
    rating: (map['rating'] as num?)?.toDouble(),
    genres: (map['genres'] as List?)?.cast<String>() ?? const [],
    overview: map['overview'] as String?,
    status: map['status'] as String?,
    episodesJson: episodes == null ? null : jsonEncode(episodes),
    chaptersJson: chapters == null ? null : jsonEncode(chapters),
  );
}
