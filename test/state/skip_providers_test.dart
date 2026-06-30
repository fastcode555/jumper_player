import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/state/skip_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('setIntro/setOutro 更新并持久化；configFor 默认 0', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(skipConfigProvider.notifier);
    expect(n.configFor('/a'), const SkipConfig());
    await n.setIntro('/a', 90);
    await n.setOutro('/a', 60);
    expect(n.configFor('/a'), const SkipConfig(introSeconds: 90, outroSeconds: 60));

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(skipConfigProvider); // 触发懒加载
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c2.read(skipConfigProvider.notifier).configFor('/a'),
        const SkipConfig(introSeconds: 90, outroSeconds: 60));
  });
}
