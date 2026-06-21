import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';

void main() {
  test('Episode equality is based on path', () {
    const a = Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1);
    const b = Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1);
    const c = Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2);
    expect(a, b);
    expect(a == c, isFalse);
  });

  test('Series holds ordered episodes', () {
    const eps = [
      Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
      Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
    ];
    const s = Series(name: 'X', rootPath: '/x', episodes: eps);
    expect(s.name, 'X');
    expect(s.episodes.length, 2);
    expect(s.episodes.first.episodeNumber, 1);
  });
}
