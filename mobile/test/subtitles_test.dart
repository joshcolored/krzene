import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krzene_mobile/subtitles.dart';

void main() {
  const srt = '''
1
00:00:01,000 --> 00:00:03,000
Hello <i>world</i>

2
00:00:04.500 --> 00:00:06.000
Second line
''';

  test('parses SRT/VTT timings and returns the active cue', () {
    final track = SubtitleTrack.parse(srt, 'sample.srt');
    expect(track.cues, hasLength(2));
    expect(track.textAt(2), 'Hello world');
    expect(track.textAt(3.5), isNull);
    expect(track.textAt(5), 'Second line');
  });

  test('subtitle offset and speed change cue timing', () {
    final track = SubtitleTrack.parseBytes(utf8.encode(srt), 'sample.srt');
    expect(track.textAt(3, offsetSeconds: 1), 'Hello world');
    expect(track.textAt(1, speed: .5), isNull);
    expect(track.textAt(2, speed: .5), 'Hello world');
  });

  test('rejects files without valid cues', () {
    expect(
      () => SubtitleTrack.parse('not a subtitle', 'bad.txt'),
      throwsFormatException,
    );
  });
}
