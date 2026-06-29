import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/state/playback_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认 true', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(autoAdvanceProvider), isTrue);
  });

  test('set(false) 持久化，新容器读回 false', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(autoAdvanceProvider.notifier).set(false);
    expect(c.read(autoAdvanceProvider), isFalse);

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(autoAdvanceProvider); // trigger lazy init + _load()
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c2.read(autoAdvanceProvider), isFalse);
  });

  test('toggle 翻转', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final before = c.read(autoAdvanceProvider);
    await c.read(autoAdvanceProvider.notifier).toggle();
    expect(c.read(autoAdvanceProvider), !before);
  });
}
