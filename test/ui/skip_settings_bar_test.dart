import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/skip_providers.dart';
import 'package:jump_player/ui/skip_settings_bar.dart';

Series _series() => Series(name: 's', rootPath: '/s', groups: [
      SeriesGroup(title: 'A', dirPath: '/s/A', episodes: [
        Episode(path: '/s/A/01.mp4', fileName: '01.mp4', episodeNumber: 1),
      ]),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('无播放集时隐藏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c,
      child: const MaterialApp(home: Scaffold(body: SkipSettingsBar()))));
    await tester.pump();
    expect(find.text('片头'), findsNothing);
  });

  testWidgets('字段随配置实时刷新：设置后显示秒数（默认 0）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(c.dispose);
    await c.read(playbackQueueProvider.notifier).loadSeries(_series());
    await tester.pumpWidget(UncontrolledProviderScope(container: c,
      child: const MaterialApp(home: Scaffold(body: SkipSettingsBar()))));
    await tester.pump();

    // 未设置 → 片头字段默认 0
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '0');

    // 设置后（模拟异步加载完成 / 另一处标记）→ 字段实时刷新为秒数
    await c.read(skipConfigProvider.notifier).setIntro('/s/A', 77);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '77');
  });

  testWidgets('标记片头写入当前位置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine();
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await c.read(playbackQueueProvider.notifier).loadSeries(_series());
    await tester.pumpWidget(UncontrolledProviderScope(container: c,
      child: const MaterialApp(home: Scaffold(body: SkipSettingsBar()))));
    fake.emitDuration(const Duration(minutes: 24));
    fake.emitPosition(const Duration(seconds: 88));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mark-intro')));
    await tester.pump();
    expect(c.read(skipConfigProvider.notifier).configFor('/s/A').introSeconds, 88);
  });

  testWidgets('标记片尾写入 时长-位置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine();
    final c = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await c.read(playbackQueueProvider.notifier).loadSeries(_series());
    await tester.pumpWidget(UncontrolledProviderScope(container: c,
      child: const MaterialApp(home: Scaffold(body: SkipSettingsBar()))));
    fake.emitDuration(const Duration(seconds: 1440));
    fake.emitPosition(const Duration(seconds: 1380));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mark-outro')));
    await tester.pump();
    expect(c.read(skipConfigProvider.notifier).configFor('/s/A').outroSeconds, 60);
  });
}
