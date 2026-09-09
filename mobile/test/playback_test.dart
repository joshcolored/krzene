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
  test('providers and TMDB embed paths', () {
    expect(PlaybackSource.values.map((s) => s.label), ['CineSrc', 'Zoryva']);
    expect(
      playbackUri(source: PlaybackSource.zoryva, media: movie).toString(),
      'https://zoryva.me/embed/movie/129?color=%23e50914',
    );
    expect(
      playbackUri(
        source: PlaybackSource.zoryva,
        media: show,
        season: 2,
        episode: 3,
      ).toString(),
      'https://zoryva.me/embed/tv/1429/2/3?color=%23e50914',
    );
    final cine = playbackUri(
      source: PlaybackSource.cineSrc,
      media: show,
      season: 2,
      episode: 3,
      resumeAt: 42,
    );
    expect(cine.queryParameters, containsPair('s', '2'));
    expect(cine.queryParameters, containsPair('e', '3'));
    expect(cine.queryParameters, containsPair('t', '42'));
  });
  test('AniList maps season/cour episodes and never reuses TMDB IDs', () {
    final mapping = AnimeMapping.fromJson({
      'season': 3,
      'anilistId': 104578,
      'firstEpisode': 13,
      'lastEpisode': 22,
      'anilistFirstEpisode': 1,
    })!;
    expect(
      playbackUri(
        source: PlaybackSource.zoryva,
        media: show,
        season: 3,
        episode: 14,
        animeMappings: [mapping],
      ).path,
      '/embed/anime/104578/1/2',
    );
    expect(
      playbackUri(
        source: PlaybackSource.zoryva,
        media: show,
        season: 2,
        episode: 14,
        animeMappings: [mapping],
      ).path,
      '/embed/tv/1429/2/14',
    );
    expect(
      playbackUri(
        source: PlaybackSource.zoryva,
        media: show,
        season: 3,
        episode: 14,
        animeMappings: [
          mapping,
          const AnimeMapping(
            season: 3,
            anilistId: 5,
            firstEpisode: 1,
            lastEpisode: null,
            anilistFirstEpisode: 1,
          ),
        ],
      ).path,
      '/embed/tv/1429/3/14',
    );
    expect(AnimeMapping.fromJson({'anilistId': -1}), isNull);
  });
  testWidgets('mobile dropdown switches between only the supported sources', (
    tester,
  ) async {
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
    expect(find.text('Source · CineSrc'), findsOneWidget);
    await tester.tap(find.byTooltip('Playback source'));
    await tester.pumpAndSettle();
    expect(find.text('CineSrc'), findsOneWidget);
    expect(find.text('Zoryva'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<PlaybackSource>, 'Zoryva'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Source · Zoryva'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
