import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/name_clean_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('초기 state는 defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The initial state before async _load is defaults.
    expect(container.read(nameCleanConfigProvider), NameCleanConfig.defaults);
  });

  test('save 更新 state 并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const next = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.year},
      customSnippets: ['x'],
    );
    await container.read(nameCleanConfigProvider.notifier).save(next);
    expect(container.read(nameCleanConfigProvider).customSnippets, ['x']);

    // Verify persistence by loading directly from the store.
    final store = container.read(configStoreProvider);
    final loaded = await store.load();
    expect(loaded.customSnippets, ['x']);
    expect(loaded.enabledBuiltinRules, {BuiltinNoiseRule.year});
  });
}
