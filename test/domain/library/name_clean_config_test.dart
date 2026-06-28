import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';

void main() {
  test('defaults 启用全部内置规则且无自定义片段', () {
    expect(NameCleanConfig.defaults.enabledBuiltinRules,
        BuiltinNoiseRule.values.toSet());
    expect(NameCleanConfig.defaults.customSnippets, isEmpty);
  });

  test('encode/decode 往返保持数据', () {
    const cfg = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.latinBracketTags, BuiltinNoiseRule.year},
      customSnippets: ['HD国语中字无水印', '最新电影www.dyg7.com'],
    );
    final back = NameCleanConfig.decode(cfg.encode());
    expect(back.enabledBuiltinRules,
        {BuiltinNoiseRule.latinBracketTags, BuiltinNoiseRule.year});
    expect(back.customSnippets, ['HD国语中字无水印', '最新电影www.dyg7.com']);
  });

  test('decode 非法字符串回退 defaults', () {
    expect(NameCleanConfig.decode('not json').enabledBuiltinRules,
        BuiltinNoiseRule.values.toSet());
  });

  test('fromJson 忽略未知规则名', () {
    final cfg = NameCleanConfig.fromJson({
      'enabledBuiltinRules': ['latinBracketTags', 'somethingNew'],
      'customSnippets': <String>[],
    });
    expect(cfg.enabledBuiltinRules, {BuiltinNoiseRule.latinBracketTags});
  });
}
