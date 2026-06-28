// test/domain/library/name_cleaner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/library/name_cleaner.dart';

void main() {
  const cfg = NameCleanConfig.defaults;

  // ── Canonical test 1 ──────────────────────────────────────────────────────
  // Pure-ASCII bracket tags auto-dropped; CJK bracket content retained.
  test('canonical 1: ASCII tags dropped, CJK bracket content retained', () {
    final r = NameCleaner.clean(
      '[GM-Team][国漫][成何体统][What A Scandal][2024][01][HEVC][GB][4K].mp4',
      '成何体统 第二季',
      cfg,
    );
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '国漫 成何体统');
    expect(r.displayName, '国漫 成何体统 01');
  });

  // ── Canonical test 2a ─────────────────────────────────────────────────────
  // Custom snippet (bare text) removes matching content before bracket processing.
  test('canonical 2a: custom snippet "国漫" removes that content', () {
    final cfg2 = cfg.copyWith(customSnippets: ['国漫']);
    final r = NameCleaner.clean(
      '[GM-Team][国漫][成何体统][What A Scandal][2024][01][HEVC][GB][4K].mp4',
      '成何体统 第二季',
      cfg2,
    );
    expect(r.seriesTitle, '成何体统');
    expect(r.displayName, '成何体统 01');
  });

  // ── Canonical test 2b ─────────────────────────────────────────────────────
  // Custom snippet with brackets also works (applied before bracket processing).
  test('canonical 2b: custom snippet "[国漫]" also removes that content', () {
    final cfg2b = cfg.copyWith(customSnippets: ['[国漫]']);
    final r = NameCleaner.clean(
      '[GM-Team][国漫][成何体统][What A Scandal][2024][01][HEVC][GB][4K].mp4',
      '成何体统 第二季',
      cfg2b,
    );
    expect(r.displayName, '成何体统 01');
  });

  // ── Canonical test 3 ──────────────────────────────────────────────────────
  // CJK title with season number retained; pure-ASCII alias dropped.
  test('canonical 3: CJK title + season retained, ASCII alias dropped', () {
    final r = NameCleaner.clean(
      '[GM-Team][国漫][逆天邪神 第2季][Against the Gods][2026][01][HEVC][4K].mp4',
      'x',
      cfg,
    );
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '国漫 逆天邪神 第2季');
    expect(r.displayName, '国漫 逆天邪神 第2季 01');
  });

  // ── Canonical test 4 ──────────────────────────────────────────────────────
  // Numeric filename falls back to parent directory name.
  test('canonical 4: numeric stem falls back to parent dir name', () {
    final r = NameCleaner.clean('01.1080p.mp4', '柯南', cfg);
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '柯南');
    expect(r.displayName, '柯南 01');
  });

  // ── Canonical test 5 ──────────────────────────────────────────────────────
  // With latinBracketTags disabled, ASCII bracket content is kept (just unwrapped).
  test('canonical 5: latinBracketTags off → ASCII bracket content retained', () {
    final cfg3 = NameCleanConfig(
      enabledBuiltinRules: {
        BuiltinNoiseRule.resolution,
        BuiltinNoiseRule.codecSource,
        BuiltinNoiseRule.year,
      },
      customSnippets: const [],
    );
    final r = NameCleaner.clean('[GM-Team][成何体统].mp4', 'x', cfg3);
    expect(r.displayName, contains('GM-Team'));
  });

  // ── Canonical test 6 ──────────────────────────────────────────────────────
  // cleanDir: ASCII bracket tag dropped, CJK retained, year dropped.
  test('canonical 6: cleanDir drops ASCII tag, keeps CJK, drops year', () {
    expect(
      NameCleaner.cleanDir('[GM-Team][国漫]逆天邪神[2024]', cfg),
      '国漫 逆天邪神',
    );
  });

  // ── Legacy compatibility tests ────────────────────────────────────────────
  test('中文第N集：集号被剥离、季号保留', () {
    final r = NameCleaner.clean('逆天邪神 第2季 第05集.mp4', 'Downloads', cfg);
    expect(r.episodeNumber, 5);
    expect(r.seriesTitle, '逆天邪神 第2季');
    expect(r.displayName, '逆天邪神 第2季 05');
  });

  test('无剧名只剩集号 + 自定义片段 → 回退父文件夹名', () {
    // Under the new model, [最新电影www.dyg7.com] is CJK-containing so bracket
    // content is retained unless the full URL is also a custom snippet.
    final c = cfg.copyWith(customSnippets: ['HD国语中字无水印', '最新电影www.dyg7.com']);
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
}
