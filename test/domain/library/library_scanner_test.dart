import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_scanner.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File touch(String name) => File('${tmp.path}/$name')..writeAsStringSync('x');

  test('按识别出的剧名分组、组内按集号排序', () async {
    touch('逆天邪神 第2季 第02集.mp4');
    touch('逆天邪神 第2季 第10集.mp4');
    touch('逆天邪神 第2季 第01集.mp4');
    touch('成何体统 第01集.mp4');

    final series = await LibraryScanner().scan(tmp.path);
    final titles = series.groups.map((g) => g.title).toList();
    expect(titles, containsAll(['逆天邪神 第2季', '成何体统']));

    final ntx = series.groups.firstWhere((g) => g.title == '逆天邪神 第2季');
    expect(ntx.episodes.map((e) => e.episodeNumber), [1, 2, 10]);
    expect(ntx.episodes.first.displayName, '逆天邪神 第2季 01');
  });

  test('只有视频扩展名被收录', () async {
    touch('a 第01集.mp4');
    touch('note.txt');
    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.length, 1);
  });
}
