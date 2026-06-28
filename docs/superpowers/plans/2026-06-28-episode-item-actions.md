# 剧集项操作（两行显示 + more 菜单：打开所在位置 / 真·重命名）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 侧边栏每个剧集项支持两行显示，末尾加 ⋮ more 菜单，提供「打开所在位置」（在访达/资源管理器中定位文件）和「重命名」（真实重命名磁盘文件）。

**Architecture:** 新增 infra `FileSystemOps`（reveal 用 `Process.run` 平台命令、rename 用 `dart:io File.rename`，命令拼装为可测纯函数 + 注入式 runner）；`LibraryActions` 增加 `revealEpisode` / `renameEpisode`（重命名后重扫并按新路径保持播放）；`EpisodeSidebar` 改两行 + `PopupMenuButton` + 重命名对话框。

**Tech Stack:** Flutter 3.27、hooks_riverpod、dart:io。

## Global Constraints
- 重命名只改主名，**自动保留原扩展名**；预填当前真实文件主名（非清洗显示名）。
- 「打开」= 在访达/资源管理器中**定位高亮**该文件（reveal），不是用播放器打开。
- 重命名后：重扫当前文件夹，若改的是正在播放那一集，用**新路径**重新定位 currentIndex，引擎不重开、不中断。
- reveal 跨平台命令：macOS `open -R <path>`；Windows `explorer /select,<path>`；Linux `xdg-open <父目录>`。
- 校验：新主名非空、不含 `/` 或 `\`、目标文件不存在（冲突报错）。
- 全程 `flutter test` 全绿、`flutter analyze` 0 issue；每任务一次提交。

---

### Task 1: infra FileSystemOps（reveal + rename）

**Files:**
- Create: `lib/infra/fs/file_system_ops.dart`
- Test: `test/infra/fs/file_system_ops_test.dart`

**Interfaces:**
- Produces:
  - `typedef ProcessRunner = Future<void> Function(String executable, List<String> args);`
  - `({String executable, List<String> args}) revealCommand(String path, {required String os});` // os ∈ {'macos','windows','linux'}; 纯函数，可单测
  - `abstract class FileSystemOps { Future<void> reveal(String path); Future<String> rename(String path, String newBaseName); }`
  - `class DefaultFileSystemOps implements FileSystemOps { DefaultFileSystemOps({ProcessRunner? runner, String? osOverride}); }`

- [ ] **Step 1: 写失败测试**

```dart
// test/infra/fs/file_system_ops_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/infra/fs/file_system_ops.dart';

void main() {
  group('revealCommand', () {
    test('macOS uses open -R', () {
      final c = revealCommand('/a/b.mp4', os: 'macos');
      expect(c.executable, 'open');
      expect(c.args, ['-R', '/a/b.mp4']);
    });
    test('windows uses explorer /select', () {
      final c = revealCommand(r'C:\a\b.mp4', os: 'windows');
      expect(c.executable, 'explorer');
      expect(c.args, [r'/select,C:\a\b.mp4']);
    });
    test('linux opens parent dir', () {
      final c = revealCommand('/a/b.mp4', os: 'linux');
      expect(c.executable, 'xdg-open');
      expect(c.args, ['/a']);
    });
  });

  group('reveal', () {
    test('runs the platform command', () async {
      String? exe;
      List<String>? args;
      final ops = DefaultFileSystemOps(
        osOverride: 'macos',
        runner: (e, a) async {
          exe = e;
          args = a;
        },
      );
      await ops.reveal('/x/y.mp4');
      expect(exe, 'open');
      expect(args, ['-R', '/x/y.mp4']);
    });
  });

  group('rename', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('fsops_'));
    tearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);

    test('keeps extension, returns new path', () async {
      final f = File('${tmp.path}/old.mp4')..writeAsStringSync('x');
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      final newPath = await ops.rename(f.path, '逆天邪神01');
      expect(newPath, '${tmp.path}/逆天邪神01.mp4');
      expect(File(newPath).existsSync(), isTrue);
      expect(f.existsSync(), isFalse);
    });

    test('throws on empty / separator / collision', () async {
      final f = File('${tmp.path}/a.mp4')..writeAsStringSync('x');
      File('${tmp.path}/taken.mp4').writeAsStringSync('y');
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      expect(() => ops.rename(f.path, '  '), throwsArgumentError);
      expect(() => ops.rename(f.path, 'a/b'), throwsArgumentError);
      expect(() => ops.rename(f.path, 'taken'), throwsA(isA<FileSystemException>()));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/infra/fs/file_system_ops_test.dart`
Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现**

```dart
// lib/infra/fs/file_system_ops.dart
import 'dart:io';

typedef ProcessRunner = Future<void> Function(
    String executable, List<String> args);

({String executable, List<String> args}) revealCommand(String path,
    {required String os}) {
  switch (os) {
    case 'windows':
      return (executable: 'explorer', args: ['/select,$path']);
    case 'linux':
      final dir = _parentDir(path);
      return (executable: 'xdg-open', args: [dir]);
    case 'macos':
    default:
      return (executable: 'open', args: ['-R', path]);
  }
}

abstract class FileSystemOps {
  Future<void> reveal(String path);

  /// Renames the file at [path] to [newBaseName] + original extension, in the
  /// same directory. Returns the new path. Throws [ArgumentError] for an empty
  /// or separator-containing name, and [FileSystemException] on collision.
  Future<String> rename(String path, String newBaseName);
}

class DefaultFileSystemOps implements FileSystemOps {
  DefaultFileSystemOps({ProcessRunner? runner, String? osOverride})
      : _run = runner ?? _defaultRun,
        _os = osOverride ?? _currentOs();

  final ProcessRunner _run;
  final String _os;

  static Future<void> _defaultRun(String e, List<String> a) async {
    await Process.run(e, a);
  }

  static String _currentOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'macos';
  }

  @override
  Future<void> reveal(String path) async {
    final c = revealCommand(path, os: _os);
    await _run(c.executable, c.args);
  }

  @override
  Future<String> rename(String path, String newBaseName) async {
    final base = newBaseName.trim();
    if (base.isEmpty || base.contains('/') || base.contains(r'\')) {
      throw ArgumentError('Invalid file name: "$newBaseName"');
    }
    final dir = _parentDir(path);
    final ext = _extension(path);
    final newPath = '$dir/$base$ext';
    if (newPath != path && File(newPath).existsSync()) {
      throw FileSystemException('Target already exists', newPath);
    }
    await File(path).rename(newPath);
    return newPath;
  }
}

String _parentDir(String path) {
  final norm = path.endsWith('/') || path.endsWith('\\')
      ? path.substring(0, path.length - 1)
      : path;
  final i = norm.lastIndexOf('/') > norm.lastIndexOf('\\')
      ? norm.lastIndexOf('/')
      : norm.lastIndexOf('\\');
  return i >= 0 ? norm.substring(0, i) : norm;
}

String _extension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i) : '';
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/infra/fs/file_system_ops_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/infra/fs/file_system_ops.dart test/infra/fs/file_system_ops_test.dart
git commit -m "feat: FileSystemOps for reveal-in-folder and real rename"
```

---

### Task 2: LibraryActions reveal/rename + provider

**Files:**
- Modify: `lib/state/library_actions.dart`
- Test: `test/state/library_actions_test.dart`

**Interfaces:**
- Consumes: `FileSystemOps`（Task 1）、`playbackQueueProvider`、`nameCleanConfigProvider`、`LibraryScanner`
- Produces:
  - `final fileSystemOpsProvider = Provider<FileSystemOps>((ref) => DefaultFileSystemOps());`
  - `LibraryActions.revealEpisode(Episode ep)` → `ops.reveal(ep.path)`
  - `LibraryActions.renameEpisode(Episode ep, String newBaseName)` → rename on disk, then re-scan current root and remap preserving playback by the NEW path.

- [ ] **Step 1: 写失败测试**（追加到 library_actions_test.dart）

```dart
  test('renameEpisode renames on disk and keeps playing the same episode', () async {
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
```

加测试用假实现（放文件顶部）：

```dart
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
}
```

> 注：`renameEpisode` 测试用**真实** DefaultFileSystemOps（默认 provider，真实 File.rename 临时目录）；`revealEpisode` 测试用注入的 `_FakeOps`。`FakePlayerEngine` 需有 `openCount`（Task 4 of 上个特性已加；若没有，加一个 int openCount 在 open() 自增——确认已存在）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/state/library_actions_test.dart`
Expected: FAIL（方法/provider 不存在）。

- [ ] **Step 3: 实现**（在 library_actions.dart 增补）

```dart
// imports: add
import 'package:jump_player/domain/library/library_models.dart'; // 若已存在勿重复
import 'package:jump_player/infra/fs/file_system_ops.dart';

// provider (file bottom, near libraryActionsProvider)
final fileSystemOpsProvider =
    Provider<FileSystemOps>((ref) => DefaultFileSystemOps());

// in class LibraryActions: add a FileSystemOps via ref
FileSystemOps get _ops => _ref.read(fileSystemOpsProvider);

Future<void> revealEpisode(Episode ep) => _ops.reveal(ep.path);

Future<void> renameEpisode(Episode ep, String newBaseName) async {
  final newPath = await _ops.rename(ep.path, newBaseName);
  final root = _currentRoot;
  if (root == null) return;
  final config = _ref.read(nameCleanConfigProvider);
  final series = await _scanner.scan(root, config);
  _queue.remapSeriesByPath(series, oldPath: ep.path, newPath: newPath);
}
```

并在 `PlaybackQueueController` 增加按路径迁移的 remap（保持播放、引擎不重开）：

```dart
// lib/state/playback_queue.dart
/// Swap in a re-scanned series after a rename. If [oldPath] was the current
/// episode, point currentIndex at [newPath]; otherwise preserve by current path.
void remapSeriesByPath(Series series,
    {required String oldPath, required String newPath}) {
  final currentPath = state.currentEpisode?.path;
  final targetPath = currentPath == oldPath ? newPath : currentPath;
  final eps = series.episodes;
  final idx =
      targetPath == null ? -1 : eps.indexWhere((e) => e.path == targetPath);
  state = PlaybackQueueState(series: series, currentIndex: idx < 0 ? -1 : idx);
}
```

- [ ] **Step 4: 跑测试确认通过 + 全量 + analyze**

Run: `flutter test && flutter analyze`
Expected: All tests passed；No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/state/library_actions.dart lib/state/playback_queue.dart test/state/library_actions_test.dart
git commit -m "feat: reveal and real-rename episode actions in LibraryActions"
```

---

### Task 3: 侧边栏两行 + more 菜单 + 重命名对话框

**Files:**
- Modify: `lib/ui/episode_sidebar.dart`
- Create: `lib/ui/rename_episode_dialog.dart`
- Test: `test/ui/episode_sidebar_test.dart`、`test/ui/rename_episode_dialog_test.dart`

**Interfaces:**
- Consumes: `libraryActionsProvider`（revealEpisode/renameEpisode）、`Episode`
- Produces: 集项 `Text(maxLines:2, ellipsis)` + 行尾 `PopupMenuButton`（值 `reveal`/`rename`）；`showRenameEpisodeDialog(context, ref, episode)`。

- [ ] **Step 1: 写失败测试**

```dart
// 追加到 test/ui/episode_sidebar_test.dart
  testWidgets('每个剧集项有两行标题与 more 菜单（打开所在位置/重命名）', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    await container.read(playbackQueueProvider.notifier).loadSeries(
          singleGroupSeries([
            Episode(path: '/x/e1.mkv', fileName: 'e1.mkv',
                displayName: '很长很长的名字需要换行展示的剧集 01', episodeNumber: 1),
          ], name: 'X'),
        );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EpisodeSidebar())),
    ));
    await tester.pump();

    // 标题两行
    final title = tester.widget<Text>(find.text('很长很长的名字需要换行展示的剧集 01'));
    expect(title.maxLines, 2);

    // more 菜单
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('打开所在位置'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
  });
```

```dart
// test/ui/rename_episode_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/ui/rename_episode_dialog.dart';

class _RecordingActions implements LibraryActions {
  String? renamedTo;
  @override
  Future<void> renameEpisode(Episode ep, String newBaseName) async {
    renamedTo = newBaseName;
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('预填真实文件主名（不含扩展名），确认后调用 renameEpisode', (tester) async {
    final actions = _RecordingActions();
    await tester.pumpWidget(ProviderScope(
      overrides: [libraryActionsProvider.overrideWithValue(actions)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showRenameEpisodeDialog(ctx,
                  Episode(path: '/d/逆天邪神01.2160p.mp4', fileName: '逆天邪神01.2160p.mp4')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 预填真实主名（去扩展名）
    expect(find.text('逆天邪神01.2160p'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '逆天邪神 01');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(actions.renamedTo, '逆天邪神 01');
  });
}
```

> 注：`_RecordingActions` 用 `noSuchMethod` 兜底未用到的方法；`showRenameEpisodeDialog` 接受 `BuildContext` 与 `Episode`，内部用 `Consumer`/`ref` 读 `libraryActionsProvider`（或接受 ref）。实现时确保对话框能从 widget tree 拿到 ProviderScope。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/episode_sidebar_test.dart test/ui/rename_episode_dialog_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现 rename 对话框**

```dart
// lib/ui/rename_episode_dialog.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';

String _baseName(String fileName) {
  final i = fileName.lastIndexOf('.');
  return i > 0 ? fileName.substring(0, i) : fileName;
}

Future<void> showRenameEpisodeDialog(BuildContext context, Episode ep) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameDialog(episode: ep),
  );
}

class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.episode});
  final Episode episode;
  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: _baseName(widget.episode.fileName));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _c.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(libraryActionsProvider).renameEpisode(widget.episode, name);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(hintText: '新文件名（自动保留扩展名）'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
```

- [ ] **Step 4: 实现侧边栏两行 + more 菜单**

把每个剧集 `ListTile` 改为：

```dart
rows.add(ListTile(
  dense: true,
  selected: selected,
  selectedTileColor: Colors.white24,
  title: Text(
    ep.displayName,
    style: TextStyle(color: selected ? Colors.amber : Colors.white),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
  trailing: PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert, color: Colors.white70),
    onSelected: (v) {
      if (v == 'reveal') {
        ref.read(libraryActionsProvider).revealEpisode(ep);
      } else if (v == 'rename') {
        showRenameEpisodeDialog(context, ep);
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'reveal', child: Text('打开所在位置')),
      PopupMenuItem(value: 'rename', child: Text('重命名')),
    ],
  ),
  onTap: () => controller.playAt(idx),
));
```

并在文件顶部 `import 'package:jump_player/state/library_actions.dart';` 与 `rename_episode_dialog.dart`。

- [ ] **Step 5: 跑测试确认通过 + 全量 + analyze**

Run: `flutter test && flutter analyze`
Expected: All tests passed；No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/episode_sidebar.dart lib/ui/rename_episode_dialog.dart test/ui/
git commit -m "feat: two-line episode rows with reveal/rename more-menu"
```

---

## Self-Review
- 两行显示 → T3 Step 4（maxLines:2）。more 菜单（打开所在位置/重命名）→ T3。reveal 跨平台 → T1。真·重命名保留扩展名 + 校验 → T1；重命名后保持播放 → T2（remapSeriesByPath）。
- 类型一致性：`FileSystemOps.reveal/rename`、`fileSystemOpsProvider`、`LibraryActions.revealEpisode/renameEpisode`、`PlaybackQueueController.remapSeriesByPath`、`showRenameEpisodeDialog(context, episode)` 跨任务签名一致。
- 依赖确认：`FakePlayerEngine.openCount` 需存在（上个特性已加）；若缺，T2 实现时补。
