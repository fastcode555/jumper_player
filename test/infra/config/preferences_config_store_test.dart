import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/infra/config/preferences_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无存储值时 load 返回 defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesConfigStore();
    final cfg = await store.load();
    expect(cfg.enabledBuiltinRules, BuiltinNoiseRule.values.toSet());
  });

  test('save 后 load 往返一致', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesConfigStore();
    const cfg = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.resolution},
      customSnippets: ['最新电影www.dyg7.com'],
    );
    await store.save(cfg);
    final back = await store.load();
    expect(back.enabledBuiltinRules, {BuiltinNoiseRule.resolution});
    expect(back.customSnippets, ['最新电影www.dyg7.com']);
  });
}
