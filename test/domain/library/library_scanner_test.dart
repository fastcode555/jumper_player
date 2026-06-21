import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_scanner.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_test_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('flat layout: sorts by episode, skips non-video', () async {
    File('${tmp.path}/吞噬星空第2集.mp4').writeAsStringSync('x');
    File('${tmp.path}/吞噬星空第10集.mp4').writeAsStringSync('x');
    File('${tmp.path}/吞噬星空第1集.mp4').writeAsStringSync('x');
    File('${tmp.path}/字幕.ass').writeAsStringSync('x');

    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.map((e) => e.episodeNumber), [1, 2, 10]);
    expect(
      series.episodes.every((e) => e.fileName.endsWith('.mp4')),
      isTrue,
    );
  });

  test('nested layout (one episode per subfolder) flattens to ordered list',
      () async {
    Directory('${tmp.path}/E01').createSync();
    Directory('${tmp.path}/E02').createSync();
    File('${tmp.path}/E01/show.S01E01.mkv').writeAsStringSync('x');
    File('${tmp.path}/E02/show.S01E02.mkv').writeAsStringSync('x');

    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.length, 2);
    expect(series.episodes.map((e) => e.episodeNumber), [1, 2]);
  });

  test('series name is the root folder name', () async {
    final sub = Directory('${tmp.path}/权力的游戏')..createSync();
    File('${sub.path}/S01E01.mkv').writeAsStringSync('x');
    final series = await LibraryScanner().scan(sub.path);
    expect(series.name, '权力的游戏');
  });
}
