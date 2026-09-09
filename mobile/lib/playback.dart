import 'models.dart';

enum PlaybackSource {
  cineSrc('CineSrc', 'https://cinesrc.st'),
  zoryva('Zoryva', 'https://zoryva.me');

  const PlaybackSource(this.label, this.host);
  final String label;
  final String host;
}

Uri playbackUri({
  required PlaybackSource source,
  required Media media,
  int season = 1,
  int episode = 1,
  int resumeAt = 0,
  List<AnimeMapping> animeMappings = const [],
}) {
  if (media.tmdbId < 1 || season < 1 || episode < 1) {
    throw ArgumentError('Playback requires positive media and episode IDs.');
  }
  if (source == PlaybackSource.zoryva) {
    final matches = <String, (int, int)>{};
    for (final mapping in animeMappings) {
      if (mapping.season != season ||
          episode < mapping.firstEpisode ||
          (mapping.lastEpisode != null && episode > mapping.lastEpisode!)) {
        continue;
      }
      final target =
          mapping.anilistFirstEpisode + episode - mapping.firstEpisode;
      matches['${mapping.anilistId}:$target'] = (mapping.anilistId, target);
    }
    final anime = matches.length == 1 ? matches.values.single : null;
    final path = anime != null
        ? '/embed/anime/${anime.$1}/1/${anime.$2}'
        : media.isSeries
        ? '/embed/tv/${media.tmdbId}/$season/$episode'
        : '/embed/movie/${media.tmdbId}';
    return Uri.parse(
      '${source.host}$path',
    ).replace(queryParameters: {'color': '#e50914'});
  }
  return Uri.parse(
    '${source.host}/embed/${media.isSeries ? 'tv' : 'movie'}/${media.tmdbId}',
  ).replace(
    queryParameters: {
      if (media.isSeries) 's': '$season',
      if (media.isSeries) 'e': '$episode',
      'autoplay': 'true',
      'muted': 'false',
      'controls': 'true',
      'continueprompt': 'false',
      if (resumeAt > 0) 't': '$resumeAt',
    },
  );
}
