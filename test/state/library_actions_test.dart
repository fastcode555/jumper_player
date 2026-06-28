import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/infra/fs/file_system_ops.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/name_clean_providers.dart';

class _FakeOps implements FileSystemOps {
  _FakeOps(this.calls);
  final List<String> calls;
  @override
  Future<void> reveal(String path) async => calls.add('reveal:$path');
  @override
  Future<String> rename(String path, String newBaseName) async {
    calls.add('rename:$path:$newBaseName');
    return path;
  }

  @override
  Future<void> moveToTrash(String path) async => calls.add('moveToTrash:$path');

  @override
  Future<String> renameDirectory(String dirPath, String newName) async {
    calls.add('renameDirectory:$dirPath:$newName');
    return dirPath;
  }
}

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

    // Sub-folder containing files with a noise token "1080p" that the resolution
    // rule will strip from displayName. With folder-based grouping the group
    // title comes from the folder name, not from the file's series title.
    final sub = Directory('${tmp.path}/逆天邪神 1080p')..createSync();
    File('${sub.path}/第01集.mp4').writeAsStringSync('x');
    File('${sub.path}/第02集.mp4').writeAsStringSync('x');

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

    // With resolution rule ON, the group title (folder basename cleaned)
    // should not contain "1080p".
    final titleBefore = stateBefore.series?.groups.first.title ?? '';
    expect(titleBefore, isNot(contains('1080p')));

    // Save a new config: disable ALL builtin rules so "1080p" is preserved
    // in the group title.
    final newConfig = NameCleanConfig(
      enabledBuiltinRules: const {},
      customSnippets: const [],
    );
    await container.read(nameCleanConfigProvider.notifier).save(newConfig);

    // Record engine open count before reapply.
    final openCountBefore = fake.openCount;

    // reapplyCurrent rescans with the new config.
    await container.read(libraryActionsProvider).reapplyCurrent();

    final stateAfter = container.read(playbackQueueProvider);
    expect(stateAfter.episodes.length, 2);

    // With builtin rules OFF, "1080p" should now appear in the group title
    // (folder name no longer cleaned of resolution tokens).
    final titleAfter = stateAfter.series?.groups.first.title ?? '';
    expect(titleAfter, contains('1080p'));

    // Currently-playing episode path must be preserved.
    expect(stateAfter.currentEpisode?.path, equals(ep1PathBefore));

    // Engine must NOT have been re-opened (playback not interrupted).
    expect(fake.openCount, equals(openCountBefore),
        reason: 'reapplyCurrent must not call engine.open()');
    expect(fake.openedPath, equals(ep1PathBefore),
        reason: 'openedPath must still be the original episode');
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

  test('renameEpisode renames on disk and keeps playing the same episode', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('rename_');
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    File('${tmp.path}/第01集.mp4').writeAsStringSync('x');
    File('${tmp.path}/第02集.mp4').writeAsStringSync('x');

    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    // play episode 2
    await container.read(playbackQueueProvider.notifier).playAt(1);
    final openCountBefore = fake.openCount;
    final ep2 = container.read(playbackQueueProvider).currentEpisode!;

    await actions.renameEpisode(ep2, '第02集-改');

    final state = container.read(playbackQueueProvider);
    // still 2 episodes, current still points to the renamed file, engine not reopened
    expect(state.episodes.length, 2);
    expect(state.currentEpisode!.path, endsWith('第02集-改.mp4'));
    expect(File('${tmp.path}/第02集-改.mp4').existsSync(), isTrue);
    expect(fake.openCount, openCountBefore); // playback not interrupted
  });

  test('revealEpisode calls ops.reveal with the episode path', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      fileSystemOpsProvider.overrideWithValue(_FakeOps(calls)),
    ]);
    addTearDown(container.dispose);
    await container
        .read(libraryActionsProvider)
        .revealEpisode(Episode(path: '/x/y.mp4', fileName: 'y.mp4'));
    expect(calls, ['reveal:/x/y.mp4']);
  });

  test('deleteEpisode trashes file and cascades folder when no videos remain',
      () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('del_');
    addTearDown(
        () => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/show').createSync();
    File('${tmp.path}/show/01.mp4').writeAsStringSync('x');
    File('${tmp.path}/show/.01.mp4.js').writeAsStringSync('x'); // sidecar junk

    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      // force permanent-delete fallback so the test can observe disk state
      fileSystemOpsProvider.overrideWithValue(
          DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {})),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final ep = container.read(playbackQueueProvider).episodes.first;

    await actions.deleteEpisode(ep);

    expect(File('${tmp.path}/show/01.mp4').existsSync(), isFalse);
    expect(Directory('${tmp.path}/show').existsSync(),
        isFalse); // cascaded (sidecar gone too)
    expect(container.read(playbackQueueProvider).episodes.isEmpty, isTrue);
  });

  test('deleteEpisode keeps folder when other videos remain', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('del2_');
    addTearDown(
        () => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/show').createSync();
    File('${tmp.path}/show/01.mp4').writeAsStringSync('x');
    File('${tmp.path}/show/02.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      fileSystemOpsProvider.overrideWithValue(
          DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {})),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final ep = container.read(playbackQueueProvider).episodes.first;
    await actions.deleteEpisode(ep);
    expect(Directory('${tmp.path}/show').existsSync(), isTrue);
    expect(container.read(playbackQueueProvider).episodes.length, 1);
  });

  test('renameFolder renames dir and refreshes; root group guarded', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('rnf_');
    addTearDown(
        () => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/old').createSync();
    File('${tmp.path}/old/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final g = container
        .read(playbackQueueProvider)
        .series!
        .groups
        .firstWhere((e) => e.dirPath == '${tmp.path}/old');
    await actions.renameFolder(g, 'new');
    expect(Directory('${tmp.path}/new').existsSync(), isTrue);
    expect(
        container
            .read(playbackQueueProvider)
            .series!
            .groups
            .any((e) => e.dirPath == '${tmp.path}/new'),
        isTrue);
  });

  test('revealFolder calls ops.reveal with group.dirPath', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      fileSystemOpsProvider.overrideWithValue(_FakeOps(calls)),
    ]);
    addTearDown(container.dispose);
    final group = SeriesGroup(
        title: 'Show', episodes: [], dirPath: '/x/show');
    await container.read(libraryActionsProvider).revealFolder(group);
    expect(calls, ['reveal:/x/show']);
  });

  test('deleteFolder trashes dir and refreshes; root group guarded', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('delf_');
    addTearDown(
        () => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/show').createSync();
    File('${tmp.path}/show/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      fileSystemOpsProvider.overrideWithValue(
          DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {})),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final g = container
        .read(playbackQueueProvider)
        .series!
        .groups
        .firstWhere((e) => e.dirPath == '${tmp.path}/show');
    await actions.deleteFolder(g);
    expect(Directory('${tmp.path}/show').existsSync(), isFalse);
    expect(container.read(playbackQueueProvider).episodes.isEmpty, isTrue);
  });

  test('isRootGroup returns true for root, false for subgroup', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('root_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/sub').createSync();
    File('${tmp.path}/sub/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final sub = container
        .read(playbackQueueProvider)
        .series!
        .groups
        .firstWhere((e) => e.dirPath == '${tmp.path}/sub');
    // root pseudo-group with dirPath == _currentRoot
    final rootGroup =
        SeriesGroup(title: 'root', episodes: [], dirPath: tmp.path);
    expect(actions.isRootGroup(rootGroup), isTrue);
    expect(actions.isRootGroup(sub), isFalse);
  });

  test('renameFolder throws StateError on root group', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('rng_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final rootGroup =
        SeriesGroup(title: 'root', episodes: [], dirPath: tmp.path);
    expect(() => actions.renameFolder(rootGroup, 'x'), throwsStateError);
  });

  test('deleteFolder throws StateError on root group', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('dfg_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final rootGroup =
        SeriesGroup(title: 'root', episodes: [], dirPath: tmp.path);
    expect(() => actions.deleteFolder(rootGroup), throwsStateError);
  });
}
