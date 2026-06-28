// test/domain/library/name_cleaner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/library/name_cleaner.dart';

void main() {
  const cfg = NameCleanConfig.defaults;

  test('括号包裹的剧名被默认规则清空 → 回退父文件夹名', () {
    final r = NameCleaner.clean(
        '[GM-Team][国漫][逆天邪神 第2季][AgeFans][01][2160p].mp4', '逆天邪神', cfg);
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '逆天邪神');
    expect(r.displayName, '逆天邪神 01');
  });

  test('中文第N集：集号被剥离、季号保留', () {
    final r = NameCleaner.clean('逆天邪神 第2季 第05集.mp4', 'Downloads', cfg);
    expect(r.episodeNumber, 5);
    expect(r.seriesTitle, '逆天邪神 第2季');
    expect(r.displayName, '逆天邪神 第2季 05');
  });

  test('无剧名只剩集号 + 自定义片段 → 回退父文件夹名', () {
    final c = cfg.copyWith(customSnippets: ['HD国语中字无水印']);
    final r = NameCleaner.clean(
        '01.2160p.HD国语中字无水印[最新电影www.dyg7.com].mkv', '成何体统', c);
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '成何体统');
    expect(r.displayName, '成何体统 01');
  });

  test('无集号：displayName 为清洗后的 stem', () {
    final r = NameCleaner.clean('阿凡达.mkv', '电影', cfg);
    expect(r.episodeNumber, isNull);
    expect(r.seriesTitle, '阿凡达');
    expect(r.displayName, '阿凡达');
  });

  test('cleanDir 去噪并归一化', () {
    expect(NameCleaner.cleanDir('[国漫]逆天邪神', cfg), '逆天邪神');
  });
}
