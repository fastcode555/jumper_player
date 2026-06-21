import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/episode_sorter.dart';

void main() {
  group('parse', () {
    test('SxxExx', () {
      final p = EpisodeSorter.parse('权游.S01E02.mkv')!;
      expect(p.season, 1);
      expect(p.episode, 2);
    });
    test('中文 第N集', () {
      expect(EpisodeSorter.parse('吞噬星空第123集.mp4')!.episode, 123);
    });
    test('中文 N集 无第', () {
      expect(EpisodeSorter.parse('吞噬星空123集.mp4')!.episode, 123);
    });
    test('分辨率干扰下仍取集号', () {
      expect(EpisodeSorter.parse('吞噬星空4K.123集.mp4')!.episode, 123);
    });
    test('EP 前缀', () {
      expect(EpisodeSorter.parse('EP123.mp4')!.episode, 123);
    });
    test('E05 而非年份/分辨率', () {
      final p = EpisodeSorter.parse('某剧.2024.1080p.E05.mkv')!;
      expect(p.episode, 5);
    });
    test('末尾独立数字兜底', () {
      expect(EpisodeSorter.parse('吞噬星空123.mp4')!.episode, 123);
    });
    test('无数字返回 null', () {
      expect(EpisodeSorter.parse('片头曲.mkv'), isNull);
    });
  });

  group('compareNatural', () {
    test('9 排在 123 前', () {
      expect(EpisodeSorter.compareNatural('ep9.mkv', 'ep123.mkv'), lessThan(0));
    });
  });

  group('sort', () {
    test('按集号数值排序而非字典序', () {
      const items = [
        Episode(path: '/a/第10集.mkv', fileName: '第10集.mkv', episodeNumber: 10),
        Episode(path: '/a/第2集.mkv', fileName: '第2集.mkv', episodeNumber: 2),
        Episode(path: '/a/第1集.mkv', fileName: '第1集.mkv', episodeNumber: 1),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.episodeNumber), [1, 2, 10]);
    });

    test('有集号的排在无集号之前；无集号按自然名', () {
      const items = [
        Episode(path: '/a/花絮.mkv', fileName: '花絮.mkv'),
        Episode(path: '/a/E2.mkv', fileName: 'E2.mkv', episodeNumber: 2),
        Episode(path: '/a/E1.mkv', fileName: 'E1.mkv', episodeNumber: 1),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.fileName), ['E1.mkv', 'E2.mkv', '花絮.mkv']);
    });

    test('按季再按集', () {
      const items = [
        Episode(path: '/a/S2E1.mkv', fileName: 'S2E1.mkv', season: 2, episodeNumber: 1),
        Episode(path: '/a/S1E2.mkv', fileName: 'S1E2.mkv', season: 1, episodeNumber: 2),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.fileName), ['S1E2.mkv', 'S2E1.mkv']);
    });
  });
}
