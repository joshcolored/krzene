class Media {
  const Media({
    required this.key,
    required this.kind,
    required this.tmdbId,
    required this.title,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.score,
    required this.genres,
    this.year,
  });

  final String key;
  final String kind;
  final int tmdbId;
  final String title;
  final int? year;
  final String overview;
  final String? poster;
  final String? backdrop;
  final double score;
  final List<String> genres;

  String? get art => backdrop ?? poster;
  bool get isSeries => kind == 'tv';

  factory Media.fromJson(Map<String, dynamic> json) => Media(
    key: json['key'] as String? ?? '',
    kind: json['kind'] as String? ?? 'movie',
    tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? 'Untitled',
    year: (json['year'] as num?)?.toInt(),
    overview: json['overview'] as String? ?? '',
    poster: json['poster'] as String?,
    backdrop: json['backdrop'] as String?,
    score: (json['score'] as num?)?.toDouble() ?? 0,
    genres: (json['genres'] as List? ?? const []).whereType<String>().toList(),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'kind': kind,
    'tmdbId': tmdbId,
    'title': title,
    'year': year,
    'overview': overview,
    'poster': poster,
    'backdrop': backdrop,
    'score': score,
    'genres': genres,
  };
}

class MediaDetail extends Media {
  MediaDetail({
    required super.key,
    required super.kind,
    required super.tmdbId,
    required super.title,
    required super.overview,
    required super.poster,
    required super.backdrop,
    required super.score,
    required super.genres,
    required this.runtime,
    required this.tagline,
    required this.seasons,
    required this.recommendations,
    super.year,
  });

  final String runtime;
  final String tagline;
  final List<SeasonInfo> seasons;
  final List<Media> recommendations;

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    final base = Media.fromJson(json);
    return MediaDetail(
      key: base.key,
      kind: base.kind,
      tmdbId: base.tmdbId,
      title: base.title,
      year: base.year,
      overview: base.overview,
      poster: base.poster,
      backdrop: base.backdrop,
      score: base.score,
      genres: base.genres,
      runtime: json['runtime'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      seasons: (json['seasons'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SeasonInfo.fromJson)
          .toList(),
      recommendations: (json['recommendations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Media.fromJson)
          .toList(),
    );
  }
}

class SeasonInfo {
  const SeasonInfo(this.number, this.name, this.episodeCount);
  final int number;
  final String name;
  final int episodeCount;

  factory SeasonInfo.fromJson(Map<String, dynamic> json) => SeasonInfo(
    (json['number'] as num?)?.toInt() ?? 1,
    json['name'] as String? ?? 'Season',
    (json['episodeCount'] as num?)?.toInt() ?? 1,
  );
}

class MediaRail {
  const MediaRail(this.id, this.kicker, this.heading, this.items);
  final String id;
  final String kicker;
  final String heading;
  final List<Media> items;

  factory MediaRail.fromJson(Map<String, dynamic> json) => MediaRail(
    json['id'] as String? ?? '',
    json['kicker'] as String? ?? '',
    json['heading'] as String? ?? '',
    (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Media.fromJson)
        .toList(),
  );
}

class HomeCatalog {
  const HomeCatalog(this.hero, this.rails, this.localeCode);
  final MediaDetail hero;
  final List<MediaRail> rails;
  final String localeCode;

  factory HomeCatalog.fromJson(Map<String, dynamic> json) {
    if (json['configured'] != true) {
      throw Exception(json['reason'] ?? 'Catalog is not configured.');
    }
    return HomeCatalog(
      MediaDetail.fromJson(json['hero'] as Map<String, dynamic>),
      (json['rails'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaRail.fromJson)
          .toList(),
      json['localeCode'] as String? ?? 'en-US',
    );
  }
}

class ViewerProfile {
  const ViewerProfile({
    required this.id,
    required this.name,
    required this.isKids,
    this.avatarUrl,
    this.avatarColor = '#e21927',
  });
  final String id;
  final String name;
  final bool isKids;
  final String? avatarUrl;
  final String avatarColor;

  factory ViewerProfile.fromJson(Map<String, dynamic> json) => ViewerProfile(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Profile',
    isKids: json['is_kids'] as bool? ?? false,
    avatarUrl: json['avatar_url'] as String?,
    avatarColor: json['avatar_color'] as String? ?? '#e21927',
  );
}

class ContinueItem {
  const ContinueItem({
    required this.media,
    required this.position,
    required this.duration,
    this.season,
    this.episode,
  });
  final Media media;
  final double position;
  final double duration;
  final int? season;
  final int? episode;

  factory ContinueItem.fromJson(Map<String, dynamic> json) => ContinueItem(
    media: Media.fromJson(json['media'] as Map<String, dynamic>),
    position: (json['position'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    season: (json['season'] as num?)?.toInt(),
    episode: (json['episode'] as num?)?.toInt(),
  );
}
