import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/infra/config/preferences_skip_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('无值返回空 map', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PreferencesSkipStore().load(), isEmpty);
  });
  test('save/load 往返', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesSkipStore();
    await store.save({'/a': const SkipConfig(introSeconds: 90, outroSeconds: 60)});
    final back = await store.load();
    expect(back['/a'], const SkipConfig(introSeconds: 90, outroSeconds: 60));
  });
  test('坏 JSON 回退空 map', () async {
    SharedPreferences.setMockInitialValues({'skip_config_v1': 'not json'});
    expect(await PreferencesSkipStore().load(), isEmpty);
  });
}
