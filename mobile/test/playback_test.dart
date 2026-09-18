import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krzene_mobile/controller.dart';
import 'package:krzene_mobile/models.dart';
import 'package:krzene_mobile/playback.dart';
import 'package:krzene_mobile/player.dart';
import 'package:krzene_mobile/services.dart';

const movie = Media(
  key: 'movie-129',
  kind: 'movie',
  tmdbId: 129,
  title: 'Test movie',
  overview: '',
  poster: null,
  backdrop: null,
  score: 8,
  genres: [],
);
const show = Media(
  key: 'tv-1429',
  kind: 'tv',
  tmdbId: 1429,
  title: 'Test show',
  overview: '',
  poster: null,
  backdrop: null,
  score: 8,
  genres: [],
);

class _Catalog extends CatalogApi {
  @override
  Future<MediaDetail> detail(Media media, String language) async => MediaDetail(
    key: media.key,
    kind: media.kind,
    tmdbId: media.tmdbId,
    title: media.title,
    overview: '',
    poster: null,
    backdrop: null,
    score: 8,
    genres: [],
    runtime: '',
    tagline: '',
    seasons: [],
    recommendations: [],
  );
}

void main() {
  test(
    'mobile only supports CineSrc and preserves episode/resume parameters',
    () {
      expect(PlaybackSource.values, [PlaybackSource.cineSrc]);
      final film = playbackUri(source: PlaybackSource.cineSrc, media: movie);
      expect(film.host, 'cinesrc.st');
      expect(film.path, '/embed/movie/129');
      final cine = playbackUri(
        source: PlaybackSource.cineSrc,
        media: show,
        season: 2,
        episode: 3,
        resumeAt: 42,
      );
      expect(cine.path, '/embed/tv/1429');
      expect(cine.queryParameters, containsPair('s', '2'));
      expect(cine.queryParameters, containsPair('e', '3'));
      expect(cine.queryParameters, containsPair('t', '42'));
      expect(cine.queryParameters, containsPair('controls', 'false'));
      expect(cine.queryParameters, containsPair('seek', '10'));
      expect(cine.queryParameters, containsPair('color', '#e21927'));
      expect(cine.queryParameters['prioritize'], isNot('true'));
      final configured = playbackUri(
        source: PlaybackSource.cineSrc,
        media: movie,
        quality: '1080',
      );
      expect(configured.queryParameters, containsPair('quality', '1080'));
      expect(configured.queryParameters, containsPair('controls', 'false'));
      expect(
        () => playbackUri(
          source: PlaybackSource.cineSrc,
          media: show,
          episode: 0,
        ),
        throwsArgumentError,
      );
    },
  );

  testWidgets('mobile player has no source selector', (tester) async {
    final controller = KrzeneController(catalogApi: _Catalog());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WatchScreen(
          media: movie,
          controller: controller,
          playerPreview: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Playback source'), findsNothing);
    expect(find.textContaining('Source ·'), findsNothing);
    expect(find.text('Zoryva'), findsNothing);
    expect(find.byTooltip('Rewind 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Playback settings'), findsOneWidget);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    expect(find.text('Preferred quality'), findsOneWidget);
    expect(find.text('Krzene subtitles'), findsOneWidget);
    expect(find.text('Subtitles, audio & servers'), findsNothing);
    expect(find.text('Volume boost'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Auto find'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.text('Customize subtitles'), findsOneWidget);
    expect(
      find.textContaining('OpenSubtitles developer consumer'),
      findsOneWidget,
    );
    expect(find.text('1.5x'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
