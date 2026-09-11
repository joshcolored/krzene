import 'models.dart';

enum PlaybackSource {
  cineSrc('CineSrc', 'https://cinesrc.st');

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
}) {
  if (media.tmdbId < 1 || season < 1 || episode < 1) {
    throw ArgumentError('Playback requires positive media and episode IDs.');
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
