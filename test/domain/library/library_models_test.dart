import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';

void main() {
  test('Episode.displayName 缺省回退 fileName', () {
    final e = Episode(path: '/a/x.mkv', fileName: 'x.mkv');
    expect(e.displayName, 'x.mkv');
  });

  test('Episode 相等基于 path', () {
    final a = Episode(path: '/a', fileName: 'a', displayName: 'A');
    final b = Episode(path: '/a', fileName: 'b', displayName: 'B');
    expect(a, b);
    expect(Episode(path: '/a', fileName: 'a') == Episode(path: '/b', fileName: 'a'), isFalse);
  });

  test('Series.episodes 展平所有组', () {
    final s = Series(name: 's', rootPath: '/s', groups: [
      SeriesGroup(title: 'g1', episodes: [Episode(path: '/1', fileName: '1')]),
      SeriesGroup(title: 'g2', episodes: [
        Episode(path: '/2', fileName: '2'),
        Episode(path: '/3', fileName: '3'),
      ]),
    ]);
    expect(s.episodes.map((e) => e.path), ['/1', '/2', '/3']);
  });
}
