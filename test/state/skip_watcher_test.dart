import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/playback_settings.dart';
import 'package:jump_player/state/skip_providers.dart';
import 'package:jump_player/state/skip_watcher.dart';

Series _series() => Series(name: 's', rootPath: '/s', groups: [
      SeriesGroup(title: 'A', dirPath: '/s/A', episodes: [
        Episode(path: '/s/A/01.mp4', fileName: '01.mp4', episodeNumber: 1),
        Episode(path: '/s/A/02.mp4', fileName: '02.mp4', episodeNumber: 2),
      ]),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('片头到点自动 seek 一次', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine();
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    c.read(skipWatcherProvider); // 启动 watcher
    await c.read(playbackQueueProvider.notifier).loadSeries(_series()); // plays index 0
    await c.read(skipConfigProvider.notifier).setIntro('/s/A', 90);
    fake.emitDuration(const Duration(minutes: 24));
    await Future<void>.delayed(Duration.zero);
    fake.emitPosition(const Duration(seconds: 3)); // 在片头内
    await Future<void>.delayed(Duration.zero);
    expect(fake.seekedTo, const Duration(seconds: 90));
  });

  test('片头 seek 被丢弃时重试，直到位置真到片头才停', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine()..dropSeeks = true; // seek 不移动位置（模拟被丢弃）
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    c.read(skipWatcherProvider);
    await c.read(playbackQueueProvider.notifier).loadSeries(_series());
    await c.read(skipConfigProvider.notifier).setIntro('/s/A', 90);
    fake.emitDuration(const Duration(minutes: 24));
    await Future<void>.delayed(Duration.zero);

    // 位置停在片头内且 seek 被丢弃 → watcher 应反复重试。
    for (var i = 0; i < 3; i++) {
      fake.emitPosition(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
    }
    expect(fake.seekCount, greaterThan(1));

    // 模拟 seek 终于生效：位置到达片头后不再重试（一次性完成）。
    final before = fake.seekCount;
    fake.emitPosition(const Duration(seconds: 90));
    await Future<void>.delayed(Duration.zero);
    fake.emitPosition(const Duration(seconds: 91));
    await Future<void>.delayed(Duration.zero);
    expect(fake.seekCount, before);
  });

  test('片尾到点：自动连播开 → next；关 → 不 next', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine();
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    c.read(skipWatcherProvider);
    await c.read(playbackQueueProvider.notifier).loadSeries(_series());
    await c.read(skipConfigProvider.notifier).setOutro('/s/A', 60);
    await c.read(autoAdvanceProvider.notifier).set(false);
    fake.emitDuration(const Duration(minutes: 24)); // 1440s
    await Future<void>.delayed(Duration.zero);
    fake.emitPosition(const Duration(seconds: 1400)); // >= 1440-60
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playbackQueueProvider).currentIndex, 0); // 未跳

    await c.read(autoAdvanceProvider.notifier).set(true);
    fake.emitPosition(const Duration(seconds: 1401));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playbackQueueProvider).currentIndex, 1); // 跳到下一集
  });
}
