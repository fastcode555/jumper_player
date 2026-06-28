import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_scanner.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File touch(String name) => File('${tmp.path}/$name')..writeAsStringSync('x');

  test('按文件所在子文件夹分组，组内按集号排序', () async {
    Directory('${tmp.path}/成何体统 第二季 01-04').createSync();
    Directory('${tmp.path}/沧元图 83.2160p').createSync();
    File('${tmp.path}/成何体统 第二季 01-04/02.1080p.mp4').writeAsStringSync('x');
    File('${tmp.path}/成何体统 第二季 01-04/01.1080p.mp4').writeAsStringSync('x');
    File('${tmp.path}/沧元图 83.2160p/83.2160p.mp4').writeAsStringSync('x');

    final series = await LibraryScanner().scan(tmp.path);
    final titles = series.groups.map((g) => g.title).toList();
    // folder names cleaned (resolution stripped): '成何体统 第二季 01-04' and '沧元图 83'
    expect(titles, containsAll(['成何体统 第二季 01-04', '沧元图 83']));
    final g = series.groups.firstWhere((e) => e.title == '成何体统 第二季 01-04');
    expect(g.episodes.map((e) => e.episodeNumber), [1, 2]); // sorted within folder
  });

  test('两个不同子文件夹即使清洗后同名也不合并', () async {
    Directory('${tmp.path}/A.2160p').createSync();
    Directory('${tmp.path}/A.1080p').createSync();
    File('${tmp.path}/A.2160p/01.mp4').writeAsStringSync('x');
    File('${tmp.path}/A.1080p/01.mp4').writeAsStringSync('x');
    final series = await LibraryScanner().scan(tmp.path);
    // both clean to title 'A' but remain two separate groups (keyed by path)
    expect(series.groups.length, 2);
    expect(series.groups.every((g) => g.title == 'A'), isTrue);
  });

  test('只有视频扩展名被收录', () async {
    touch('a 第01集.mp4');
    touch('note.txt');
    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.length, 1);
  });
}
