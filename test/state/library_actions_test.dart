import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/name_clean_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openFolder scans and loads first episode into the queue', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('lib_actions_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/第1集.mp4').writeAsStringSync('x');
    File('${tmp.path}/第2集.mp4').writeAsStringSync('x');

    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(libraryActionsProvider).openFolder(tmp.path);

    final state = container.read(playbackQueueProvider);
    expect(state.episodes.length, 2);
    expect(state.currentIndex, 0);
    expect(fake.openedPath, endsWith('第1集.mp4'));
  });

  test('reapplyCurrent 用最新配置重扫并保留当前播放项', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('lib_actions_reapply_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // Files with a noise token "1080p" that the resolution rule will strip.
    // After openFolder with defaults (resolution rule ON), displayName loses "1080p".
    // We then disable ALL builtin rules, add a custom snippet to see the change.
    File('${tmp.path}/逆天邪神 第01集 1080p.mp4').writeAsStringSync('x');
    File('${tmp.path}/逆天邪神 第02集 1080p.mp4').writeAsStringSync('x');

    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    // Open folder with default config (resolution rule enabled).
    await container.read(libraryActionsProvider).openFolder(tmp.path);

    final stateBefore = container.read(playbackQueueProvider);
    expect(stateBefore.episodes.length, 2);
    final ep1PathBefore = stateBefore.currentEpisode?.path;
    expect(ep1PathBefore, isNotNull);

    // The series title under defaults should not contain "1080p" (stripped).
    final titleBefore = stateBefore.series?.groups.first.title ?? '';
    expect(titleBefore, isNot(contains('1080p')));

    // Save a new config: disable ALL builtin rules so "1080p" is preserved,
    // and add a custom snippet that should be stripped.
    final newConfig = NameCleanConfig(
      enabledBuiltinRules: const {},
      customSnippets: const ['第01集', '第02集'],
    );
    await container.read(nameCleanConfigProvider.notifier).save(newConfig);

    // reapplyCurrent rescans with the new config.
    await container.read(libraryActionsProvider).reapplyCurrent();

    final stateAfter = container.read(playbackQueueProvider);
    expect(stateAfter.episodes.length, 2);

    // With builtin rules OFF, "1080p" should now appear in the title.
    final titleAfter = stateAfter.series?.groups.first.title ?? '';
    expect(titleAfter, contains('1080p'));

    // Currently-playing episode path must be preserved.
    expect(stateAfter.currentEpisode?.path, equals(ep1PathBefore));
  });

  test('reapplyCurrent 未打开文件夹时是 no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    // Should complete without error, queue unchanged.
    await container.read(libraryActionsProvider).reapplyCurrent();
    final state = container.read(playbackQueueProvider);
    expect(state.series, isNull);
  });
}
