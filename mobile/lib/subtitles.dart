import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'config.dart';
import 'models.dart';

class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.name,
    required this.cues,
    required this.source,
  });

  final String name;
  final List<SubtitleCue> cues;
  final String source;

  static SubtitleTrack parseBytes(Uint8List bytes, String name) {
    String source;
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      final units = <int>[];
      for (var index = 2; index + 1 < bytes.length; index += 2) {
        units.add(bytes[index] | (bytes[index + 1] << 8));
      }
      source = String.fromCharCodes(units);
    } else if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      final units = <int>[];
      for (var index = 2; index + 1 < bytes.length; index += 2) {
        units.add((bytes[index] << 8) | bytes[index + 1]);
      }
      source = String.fromCharCodes(units);
    } else {
      source = utf8.decode(bytes, allowMalformed: true);
    }
    return parse(source, name);
  }

  static SubtitleTrack parse(String source, String name) {
    final normalized = source
        .replaceFirst('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final cues = <SubtitleCue>[];
    for (final block in normalized.split(RegExp(r'\n{2,}'))) {
      final lines = block
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList();
      final timingIndex = lines.indexWhere((line) => line.contains('-->'));
      if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
      final timing = RegExp(
        r'((?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})\s*-->\s*((?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})',
      ).firstMatch(lines[timingIndex]);
      if (timing == null) continue;
      final start = _timestamp(timing.group(1)!);
      final end = _timestamp(timing.group(2)!);
      if (end <= start) continue;
      final text = lines
          .skip(timingIndex + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .trim();
      if (text.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: text));
      }
    }
    if (cues.isEmpty) {
      throw const FormatException('No valid subtitle cues were found.');
    }
    cues.sort((left, right) => left.start.compareTo(right.start));
    return SubtitleTrack(name: name, cues: cues, source: normalized);
  }

  static Duration _timestamp(String value) {
    final parts = value.replaceAll(',', '.').split(':');
    final seconds = double.parse(parts.removeLast());
    final minutes = int.parse(parts.removeLast());
    final hours = parts.isEmpty ? 0 : int.parse(parts.removeLast());
    return Duration(
      milliseconds: ((hours * 3600 + minutes * 60 + seconds) * 1000).round(),
    );
  }

  String? textAt(
    double playbackSeconds, {
    double offsetSeconds = 0,
    double speed = 1,
  }) {
    final subtitleSeconds = (playbackSeconds - offsetSeconds) * speed;
    if (subtitleSeconds < 0 || cues.isEmpty) return null;
    final at = Duration(milliseconds: (subtitleSeconds * 1000).round());
    var low = 0;
    var high = cues.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final cue = cues[middle];
      if (at < cue.start) {
        high = middle - 1;
      } else if (at > cue.end) {
        low = middle + 1;
      } else {
        final visible = <String>[cue.text];
        for (var index = middle + 1; index < cues.length; index++) {
          final next = cues[index];
          if (next.start > at) break;
          if (next.end >= at) visible.add(next.text);
        }
        return visible.join('\n');
      }
    }
    return null;
  }
}

class StoredSubtitle {
  const StoredSubtitle({
    required this.track,
    required this.enabled,
    required this.offset,
    required this.speed,
    required this.fontSize,
    required this.background,
    required this.backgroundColorValue,
    required this.colorValue,
  });

  final SubtitleTrack track;
  final bool enabled;
  final double offset;
  final double speed;
  final double fontSize;
  final double background;
  final int backgroundColorValue;
  final int colorValue;
}

class SubtitleLocalStore {
  SubtitleLocalStore._();

  static final SubtitleLocalStore instance = SubtitleLocalStore._();
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      '$root/krzene.db',
      version: 2,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE local_subtitles (
            media_key TEXT NOT NULL,
            season INTEGER NOT NULL,
            episode INTEGER NOT NULL,
            name TEXT NOT NULL,
            content TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            timing_offset REAL NOT NULL DEFAULT 0,
            timing_speed REAL NOT NULL DEFAULT 1,
            font_size REAL NOT NULL DEFAULT 20,
            background REAL NOT NULL DEFAULT 0.68,
            background_color_value INTEGER NOT NULL DEFAULT 4278190080,
            color_value INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (media_key, season, episode)
          )
        ''');
      },
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE local_subtitles ADD COLUMN background_color_value INTEGER NOT NULL DEFAULT 4278190080',
          );
        }
      },
    );
    return _database!;
  }

  Future<StoredSubtitle?> load({
    required String mediaKey,
    required int season,
    required int episode,
  }) async {
    final database = await _db;
    final rows = await database.query(
      'local_subtitles',
      where: 'media_key = ? AND season = ? AND episode = ?',
      whereArgs: [mediaKey, season, episode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    try {
      return StoredSubtitle(
        track: SubtitleTrack.parse(
          row['content'] as String,
          row['name'] as String,
        ),
        enabled: row['enabled'] == 1,
        offset: (row['timing_offset'] as num).toDouble(),
        speed: (row['timing_speed'] as num).toDouble(),
        fontSize: (row['font_size'] as num).toDouble(),
        background: (row['background'] as num).toDouble(),
        backgroundColorValue:
            (row['background_color_value'] as num?)?.toInt() ?? 0xff000000,
        colorValue: row['color_value'] as int,
      );
    } on FormatException {
      await delete(mediaKey: mediaKey, season: season, episode: episode);
      return null;
    }
  }

  Future<void> save({
    required String mediaKey,
    required int season,
    required int episode,
    required StoredSubtitle subtitle,
  }) async {
    final database = await _db;
    await database.insert('local_subtitles', {
      'media_key': mediaKey,
      'season': season,
      'episode': episode,
      'name': subtitle.track.name,
      'content': subtitle.track.source,
      'enabled': subtitle.enabled ? 1 : 0,
      'timing_offset': subtitle.offset,
      'timing_speed': subtitle.speed,
      'font_size': subtitle.fontSize,
      'background': subtitle.background,
      'background_color_value': subtitle.backgroundColorValue,
      'color_value': subtitle.colorValue,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete({
    required String mediaKey,
    required int season,
    required int episode,
  }) async {
    final database = await _db;
    await database.delete(
      'local_subtitles',
      where: 'media_key = ? AND season = ? AND episode = ?',
      whereArgs: [mediaKey, season, episode],
    );
  }
}

class SubtitleService {
  const SubtitleService();

  Future<SubtitleTrack> findAutomatic({
    required Media media,
    required int season,
    required int episode,
    required String language,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/subtitles').replace(
      queryParameters: {
        'type': media.isSeries ? 'tv' : 'movie',
        'id': '${media.tmdbId}',
        'lang': language.split(RegExp('[-_]')).first,
        if (media.isSeries) 'season': '$season',
        if (media.isSeries) 'episode': '$episode',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 35));
    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw Exception('The subtitle service returned invalid data.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload is! Map) {
      final message = payload is Map ? payload['error']?.toString() : null;
      throw Exception(message ?? 'No automatic subtitle was found.');
    }
    final content = payload['content']?.toString();
    if (content == null || content.trim().isEmpty) {
      throw Exception('The subtitle service returned an empty file.');
    }
    return SubtitleTrack.parse(
      content,
      payload['name']?.toString() ?? '${media.title}.srt',
    );
  }
}
