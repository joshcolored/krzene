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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
