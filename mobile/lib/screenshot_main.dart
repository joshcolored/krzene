// Screenshot-only Flutter entrypoint for App Store artwork.
//
// Launch explicitly with:
// flutter run -t lib/screenshot_main.dart \
//   --dart-define=KRZENE_SCREENSHOT_PAGE=discover
//
// The production app continues to use lib/main.dart. No credentials or live
// account data are used here.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'controller.dart';
import 'design.dart';
import 'models.dart';
import 'player.dart';
import 'services.dart';

const screenshotPage = String.fromEnvironment(
  'KRZENE_SCREENSHOT_PAGE',
  defaultValue: 'discover',
);

final hero = MediaDetail(
  key: 'movie-860508',
  kind: 'movie',
  tmdbId: 860508,
  title: 'The Whisper Man',
  year: 2026,
  overview:
      'When his young son vanishes, a widower enlists help from his estranged father, a retired detective who put away the serial killer now linked to the case.',
  poster: 'https://image.tmdb.org/t/p/w500/6UqflU8Qqkz7Dq4swJPqs0ZJjY4.jpg',
  backdrop:
      'https://image.tmdb.org/t/p/original/xSJJQeAp9GBFmiKusysTRG6jQjt.jpg',
  score: 6.6,
  genres: ['Crime', 'Drama', 'Thriller'],
  runtime: '1h 42m',
  tagline: 'Some voices never leave you.',
  seasons: [],
  recommendations: screenshotMedia,
);

const screenshotMedia = <Media>[
  Media(
    key: 'movie-1288445',
    kind: 'movie',
    tmdbId: 1288445,
    title: 'Mutiny',
    year: 2026,
    overview:
        'After witnessing his billionaire boss’ murder, Cole Reed uncovers an international conspiracy.',
    poster: 'https://image.tmdb.org/t/p/w500/pu2VxGlpGwffOx292w18b1tv96j.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/qDa0fqDqIBCovRp975RvtGPcuN3.jpg',
    score: 6.4,
    genres: ['Action', 'Thriller'],
  ),
  Media(
    key: 'movie-1368337',
    kind: 'movie',
    tmdbId: 1368337,
    title: 'The Odyssey',
    year: 2026,
    overview: 'Odysseus embarks on a long and perilous journey home.',
    poster: 'https://image.tmdb.org/t/p/w500/5rhTDKUhPYvpdQIijFIs5VoWsON.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/RMXG8myu1aGlNUsRjtxzmpdMK0.jpg',
    score: 8,
    genres: ['Adventure', 'Action', 'Fantasy'],
  ),
  Media(
    key: 'movie-969681',
    kind: 'movie',
    tmdbId: 969681,
    title: 'Spider-Man: Brand New Day',
    year: 2026,
    overview: 'Peter Parker faces a new threat in a world that forgot him.',
    poster: 'https://image.tmdb.org/t/p/w500/bjiS5ipwxb9JFy3XRRN4OAilSeX.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/7iwUUcKURMT7aKfCwMy6YnGtchD.jpg',
    score: 7.9,
    genres: ['Science Fiction', 'Action'],
  ),
  Media(
    key: 'movie-1386315',
    kind: 'movie',
    tmdbId: 1386315,
    title: 'The Runner',
    year: 2026,
    overview: 'A mother must keep running to save her kidnapped son.',
    poster: 'https://image.tmdb.org/t/p/w500/uxCaBoYXsDC4A0SqTm3SISj0OwK.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/jzBWExXacS33rMQ2zLBrqIVweyG.jpg',
    score: 5.7,
    genres: ['Action', 'Thriller'],
  ),
  Media(
    key: 'tv-95350',
    kind: 'tv',
    tmdbId: 95350,
    title: 'Lanterns',
    year: 2026,
    overview: 'Two intergalactic cops investigate a murder on Earth.',
    poster: 'https://image.tmdb.org/t/p/w500/gpC7h43xPMEV3goYMQShfJbTtLq.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/mdbWfpbWhvxgG3k5MHpo90UgAUe.jpg',
    score: 8.3,
    genres: ['Drama', 'Mystery'],
  ),
  Media(
    key: 'tv-125988',
    kind: 'tv',
    tmdbId: 125988,
    title: 'Silo',
    year: 2023,
    overview: 'Thousands live in a giant silo beneath a ruined world.',
    poster: 'https://image.tmdb.org/t/p/w500/gMYZZvnkVNTqSVnVCphWbPXwWwb.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/uTWhbLc7Bj4qNSdW3ZvZKL8cOHv.jpg',
    score: 8.2,
    genres: ['Science Fiction', 'Drama'],
  ),
  Media(
    key: 'tv-108978',
    kind: 'tv',
    tmdbId: 108978,
    title: 'Reacher',
    year: 2022,
    overview: 'A veteran military police investigator enters civilian life.',
    poster: 'https://image.tmdb.org/t/p/w500/f1VCQIG2iCyOookdgOzwtUpwWC0.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/pF0qkRsrHkdYadPWY9AMeFZfcwk.jpg',
    score: 8.1,
    genres: ['Action', 'Crime'],
  ),
  Media(
    key: 'movie-1084244',
    kind: 'movie',
    tmdbId: 1084244,
    title: 'Toy Story 5',
    year: 2026,
    overview: 'Buzz, Woody, and Jessie face an all-new threat to playtime.',
    poster: 'https://image.tmdb.org/t/p/w500/sfQtVlIHljToOwYjhe21KPGzZWK.jpg',
    backdrop:
        'https://image.tmdb.org/t/p/original/8sSKdEmlmqF4kJUd28SqthXC4yZ.jpg',
    score: 8.3,
    genres: ['Animation', 'Family', 'Comedy'],
  ),
];

class ScreenshotAccount extends AccountRepository {
  @override
  User? get user => const User(
    id: 'app-store-screenshot-user',
    appMetadata: {'provider': 'email'},
    userMetadata: {'full_name': 'Joshua', 'name': 'Joshua'},
    aud: 'authenticated',
    email: 'viewer@krzene.site',
    createdAt: '2026-08-31T00:00:00.000Z',
  );

  @override
  Future<void> saveWatchProgress({
    required ViewerProfile profile,
    required Media media,
    required double position,
    required double duration,
    required bool completed,
    int? season,
    int? episode,
  }) async {}
}

class ScreenshotCatalogApi extends CatalogApi {
  const ScreenshotCatalogApi();

  @override
  Future<MediaDetail> detail(Media media, String language) async {
    if (media.key == hero.key) return hero;
    return MediaDetail(
      key: media.key,
      kind: media.kind,
      tmdbId: media.tmdbId,
      title: media.title,
      overview: media.overview,
      poster: media.poster,
      backdrop: media.backdrop,
      score: media.score,
      genres: media.genres,
      year: media.year,
      runtime: '1h 42m',
      tagline: '',
      seasons: const [],
      recommendations: screenshotMedia
          .where((item) => item.key != media.key)
          .take(6)
          .toList(),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: krzeneBackground,
    ),
  );

  final controller =
      KrzeneController(
          account: ScreenshotAccount(),
          catalogApi: const ScreenshotCatalogApi(),
        )
        ..catalog = HomeCatalog(hero, const [
          MediaRail(
            'trending',
            'JUST FOR YOU',
            'Trending this week',
            screenshotMedia,
          ),
          MediaRail(
            'movies',
            'MOVIES',
            'Stories worth watching',
            screenshotMedia,
          ),
        ], 'en-US')
        ..profiles = const [
          ViewerProfile(
            id: 'profile-joshua',
            name: 'Joshua',
            isKids: false,
            avatarColor: '#e21927',
          ),
          ViewerProfile(
            id: 'profile-knight',
            name: 'Knight',
            isKids: true,
            avatarColor: '#47c98d',
          ),
        ]
        ..activeProfile = const ViewerProfile(
          id: 'profile-joshua',
          name: 'Joshua',
          isKids: false,
          avatarColor: '#e21927',
        )
        ..library = screenshotMedia.skip(1).take(6).toList()
        ..continueWatching = [
          ContinueItem(
            media: screenshotMedia.first,
            position: 1240,
            duration: 6120,
          ),
        ]
        ..initialized = true
        ..loading = false;

  runApp(ScreenshotApp(controller: controller));
}

class ScreenshotApp extends StatefulWidget {
  const ScreenshotApp({super.key, required this.controller});

  final KrzeneController controller;

  @override
  State<ScreenshotApp> createState() => _ScreenshotAppState();
}

class _ScreenshotAppState extends State<ScreenshotApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Widget _screen() => switch (screenshotPage) {
    'discover' => HomeShell(controller: widget.controller),
    'search' => HomeShell(controller: widget.controller, initialIndex: 1),
    'library' => HomeShell(controller: widget.controller, initialIndex: 2),
    'player' => WatchScreen(
      media: screenshotMedia.last,
      controller: widget.controller,
      playerPreview: const _ScreenshotPlayerPreview(),
    ),
    'profiles' => ManageProfilesScreen(controller: widget.controller),
    _ => HomeShell(controller: widget.controller),
  };

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Krzene App Store Screenshots',
    theme: krzeneTheme(),
    home: _screen(),
  );
}

class _ScreenshotPlayerPreview extends StatelessWidget {
  const _ScreenshotPlayerPreview();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.network(
        screenshotMedia.last.backdrop!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff10233a)),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black12, Colors.black54],
          ),
        ),
      ),
      Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .58),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 2),
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 58),
        ),
      ),
      const Positioned(
        left: 28,
        right: 28,
        bottom: 24,
        child: Row(
          children: [
            Text('0:04'),
            SizedBox(width: 14),
            Expanded(
              child: LinearProgressIndicator(
                value: .08,
                minHeight: 4,
                color: Color(0xffed1b2f),
                backgroundColor: Colors.white38,
              ),
            ),
            SizedBox(width: 14),
            Text('1:41:46'),
            SizedBox(width: 20),
            Icon(Icons.fullscreen_rounded, size: 30),
          ],
        ),
      ),
    ],
  );
}
