# 分组折叠 + 文件夹/文件 删除·重命名·打开位置 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 侧边栏分组可折叠（默认收起、正在播放的组自动展开）；文件夹（组）支持打开所在位置/重命名/删除；文件新增删除，删除后若所在文件夹已无视频文件则连带删除文件夹，并刷新列表。删除一律移入**废纸篓**（可恢复）。

**Architecture:** `FileSystemOps` 增加 `moveToTrash`（macOS 用 Finder/osascript）与 `renameDirectory`；`SeriesGroup` 增加 `dirPath`（扫描时记录）；`LibraryActions` 增加 `deleteEpisode`（trash+级联删空文件夹+刷新）、`renameFolder`/`deleteFolder`/`revealFolder`（带根目录护栏）；侧边栏改自绘可折叠分组（展开集合用 provider，自动展开当前播放组），组标题加 ⋮ 菜单，文件 ⋮ 菜单加删除，删除文件夹带二次确认。

**Tech Stack:** Flutter、hooks_riverpod、dart:io、osascript(Finder)。

## Global Constraints
- 删除=移入废纸篓（macOS：`osascript` 让 Finder 删除；非 macOS 回退永久删除）。**不要**无脑永久删除。
- 删文件后：若其父目录已**无视频文件**（`LibraryScanner.videoExtensions`），把该父目录一并移入废纸篓（连同 .js 等残留）。
- 分组默认收起；**含当前播放集的组自动展开**；折叠不影响全局索引/播放定位。
- 文件夹重命名/删除：对**根目录组**（dirPath == 已打开的 rootPath）禁用（防误删整个打开目录）。
- 重命名（文件夹）：只改目录名；校验非空、不含 `/`/`\`、目标不存在。
- 删除文件夹需二次确认对话框；操作后均重扫当前库并刷新（保持播放，按当前路径 remap；被删的当前集→无选中）。
- 全程 `flutter test` 绿、`flutter analyze` 0 issue；每任务一次提交。

---

### Task 1: FileSystemOps — moveToTrash + renameDirectory

**Files:** Modify `lib/infra/fs/file_system_ops.dart`; Test `test/infra/fs/file_system_ops_test.dart`

**Interfaces (add to `FileSystemOps` + `DefaultFileSystemOps`):**
- `({String executable, List<String> args}) trashCommand(String path, {required String os});` // 纯函数，可单测；macOS 用 osascript Finder
- `Future<void> moveToTrash(String path);`
- `Future<String> renameDirectory(String dirPath, String newName);` // 同 rename 但无扩展名

- [ ] **Step 1: 失败测试**

```dart
  group('trashCommand', () {
    test('macOS uses Finder via osascript', () {
      final c = trashCommand('/a/b.mp4', os: 'macos');
      expect(c.executable, 'osascript');
      expect(c.args.length, 2);
      expect(c.args.first, '-e');
      expect(c.args[1], contains('Finder'));
      expect(c.args[1], contains('/a/b.mp4'));
    });
  });

  group('moveToTrash', () {
    test('runs the macOS finder command via injected runner', () async {
      String? exe; List<String>? args;
      final ops = DefaultFileSystemOps(osOverride: 'macos', runner: (e, a) async { exe = e; args = a; });
      await ops.moveToTrash('/x/y.mp4');
      expect(exe, 'osascript');
      expect(args!.join(' '), contains('/x/y.mp4'));
    });
    test('non-macOS fallback permanently deletes', () async {
      final tmp = Directory.systemTemp.createTempSync('trash_');
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
      final f = File('${tmp.path}/a.mp4')..writeAsStringSync('x');
      final ops = DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {});
      await ops.moveToTrash(f.path);
      expect(f.existsSync(), isFalse);
    });
  });

  group('renameDirectory', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rndir_'));
    tearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    test('renames dir, returns new path', () async {
      final d = Directory('${tmp.path}/old')..createSync();
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      final np = await ops.renameDirectory(d.path, '新剧名');
      expect(np, '${tmp.path}/新剧名');
      expect(Directory(np).existsSync(), isTrue);
      expect(d.existsSync(), isFalse);
    });
    test('throws on empty/separator/collision', () async {
      final d = Directory('${tmp.path}/x')..createSync();
      Directory('${tmp.path}/taken').createSync();
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      expect(() => ops.renameDirectory(d.path, ' '), throwsArgumentError);
      expect(() => ops.renameDirectory(d.path, 'a/b'), throwsArgumentError);
      expect(() => ops.renameDirectory(d.path, 'taken'), throwsA(isA<FileSystemException>()));
    });
  });
```

- [ ] **Step 2: 跑测试确认失败** — `flutter test test/infra/fs/file_system_ops_test.dart` → FAIL.

- [ ] **Step 3: 实现**（追加到 file_system_ops.dart）

```dart
// add to interface FileSystemOps:
Future<void> moveToTrash(String path);
Future<String> renameDirectory(String dirPath, String newName);

// pure command builder (top-level, like revealCommand):
({String executable, List<String> args}) trashCommand(String path,
    {required String os}) {
  // macOS: ask Finder to move the item to Trash (recoverable).
  final script =
      'tell application "Finder" to delete (POSIX file ${_appleScriptString(path)} as alias)';
  return (executable: 'osascript', args: ['-e', script]);
}

String _appleScriptString(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

// in DefaultFileSystemOps:
@override
Future<void> moveToTrash(String path) async {
  if (_os == 'macos') {
    final c = trashCommand(path, os: _os);
    await _run(c.executable, c.args);
    return;
  }
  // Fallback for non-macOS: permanent delete.
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (type != FileSystemEntityType.notFound) {
    await File(path).delete();
  }
}

@override
Future<String> renameDirectory(String dirPath, String newName) async {
  final base = newName.trim();
  if (base.isEmpty || base.contains('/') || base.contains(r'\')) {
    throw ArgumentError('Invalid folder name: "$newName"');
  }
  final parent = _parentDir(dirPath);
  final newPath = '$parent/$base';
  if (newPath != dirPath && FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) {
    throw FileSystemException('Target already exists', newPath);
  }
  await Directory(dirPath).rename(newPath);
  return newPath;
}
```

- [ ] **Step 4: 通过** — focused test PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: FileSystemOps moveToTrash + renameDirectory"`

---

### Task 2: SeriesGroup.dirPath（模型 + 扫描器记录）

**Files:** Modify `lib/domain/library/library_models.dart`, `lib/domain/library/library_scanner.dart`; Test `test/domain/library/library_scanner_test.dart`

**Interfaces:** `SeriesGroup({required title, required episodes, required String dirPath})`; 扫描器构造组时传入该组的父目录路径（map 的 key）。

- [ ] **Step 1: 失败测试**（追加到 scanner 测试）

```dart
  test('每组记录其真实目录路径 dirPath', () async {
    Directory('${tmp.path}/A').createSync();
    File('${tmp.path}/A/01.mp4').writeAsStringSync('x');
    final s = await LibraryScanner().scan(tmp.path);
    final g = s.groups.firstWhere((e) => e.title == 'A');
    expect(g.dirPath, '${tmp.path}/A');
  });
```

- [ ] **Step 2: 确认失败** — FAIL（dirPath 不存在）。

- [ ] **Step 3: 实现**
  - `SeriesGroup` 加 `final String dirPath;`，构造加 `required this.dirPath`。
  - 扫描器构造 `SeriesGroup(title: cleanDir(_baseName(dirPath)), episodes: ..., dirPath: dirPath)`（dirPath 即 groupsMap 的 key）。
  - 修任何构造 `SeriesGroup(...)` 的现有测试（episode_sidebar_test、library_models_test、playback_queue_test 的 `singleGroupSeries` helper 等）加 `dirPath:`（helper 里给个 `'/$name'`）。

- [ ] **Step 4: 全量绿 + analyze 干净** — `flutter test && flutter analyze`
- [ ] **Step 5: Commit** — `git commit -m "feat: record SeriesGroup.dirPath from scanner"`

---

### Task 3: LibraryActions — delete/rename/reveal for files & folders

**Files:** Modify `lib/state/library_actions.dart`; Test `test/state/library_actions_test.dart`

**Interfaces (add to LibraryActions):**
- `Future<void> deleteEpisode(Episode ep)` — trash file; if parent dir has no video files left, trash that dir; then re-scan + remap.
- `Future<void> revealFolder(SeriesGroup group)` — `_ops.reveal(group.dirPath)`.
- `Future<void> renameFolder(SeriesGroup group, String newName)` — guard root; `_ops.renameDirectory`; re-scan + remap.
- `Future<void> deleteFolder(SeriesGroup group)` — guard root; `_ops.moveToTrash(group.dirPath)`; re-scan + remap.
- helper `bool isRootGroup(SeriesGroup g) => g.dirPath == _currentRoot;`

- [ ] **Step 1: 失败测试**（用真实临时目录 + 注入 ops 记录调用 / 或真实 DefaultFileSystemOps 的 linux fallback 永久删除来观察磁盘效果）

```dart
  test('deleteEpisode trashes file and cascades folder when no videos remain', () async {
    final tmp = Directory.systemTemp.createTempSync('del_');
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/show').createSync();
    File('${tmp.path}/show/01.mp4').writeAsStringSync('x');
    File('${tmp.path}/show/.01.mp4.js').writeAsStringSync('x'); // sidecar junk

    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      // force permanent-delete fallback so the test can observe disk state
      fileSystemOpsProvider.overrideWithValue(DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {})),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final ep = container.read(playbackQueueProvider).episodes.first;

    await actions.deleteEpisode(ep);

    expect(File('${tmp.path}/show/01.mp4').existsSync(), isFalse);
    expect(Directory('${tmp.path}/show').existsSync(), isFalse); // cascaded (sidecar gone too)
    expect(container.read(playbackQueueProvider).episodes.isEmpty, isTrue);
  });

  test('deleteEpisode keeps folder when other videos remain', () async {
    final tmp = Directory.systemTemp.createTempSync('del2_');
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/show').createSync();
    File('${tmp.path}/show/01.mp4').writeAsStringSync('x');
    File('${tmp.path}/show/02.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      fileSystemOpsProvider.overrideWithValue(DefaultFileSystemOps(osOverride: 'linux', runner: (_, __) async {})),
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
    final tmp = Directory.systemTemp.createTempSync('rnf_');
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);
    Directory('${tmp.path}/old').createSync();
    File('${tmp.path}/old/01.mp4').writeAsStringSync('x');
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
    ]);
    addTearDown(container.dispose);
    final actions = container.read(libraryActionsProvider);
    await actions.openFolder(tmp.path);
    final g = container.read(playbackQueueProvider).series!.groups
        .firstWhere((e) => e.dirPath == '${tmp.path}/old');
    await actions.renameFolder(g, 'new');
    expect(Directory('${tmp.path}/new').existsSync(), isTrue);
    expect(container.read(playbackQueueProvider).series!.groups
        .any((e) => e.dirPath == '${tmp.path}/new'), isTrue);
  });
```

- [ ] **Step 2: 确认失败** — FAIL（方法不存在）。

- [ ] **Step 3: 实现**（在 LibraryActions 增补；需要 `import 'dart:io'` 与 `library_scanner.dart` 的 `videoExtensions`、`library_models.dart`）

```dart
Future<void> deleteEpisode(Episode ep) async {
  await _ops.moveToTrash(ep.path);
  final dir = _parentPath(ep.path);
  if (!_dirHasVideo(dir)) {
    await _ops.moveToTrash(dir);
  }
  await _rescan();
}

Future<void> revealFolder(SeriesGroup group) => _ops.reveal(group.dirPath);

Future<void> renameFolder(SeriesGroup group, String newName) async {
  if (isRootGroup(group)) {
    throw StateError('Cannot rename the opened root folder');
  }
  await _ops.renameDirectory(group.dirPath, newName);
  await _rescan();
}

Future<void> deleteFolder(SeriesGroup group) async {
  if (isRootGroup(group)) {
    throw StateError('Cannot delete the opened root folder');
  }
  await _ops.moveToTrash(group.dirPath);
  await _rescan();
}

bool isRootGroup(SeriesGroup g) => g.dirPath == _currentRoot;

Future<void> _rescan() async {
  final root = _currentRoot;
  if (root == null) return;
  final config = _ref.read(nameCleanConfigProvider);
  final series = await _scanner.scan(root, config);
  _queue.remapSeries(series); // keep playing by current path; gone -> -1
}

bool _dirHasVideo(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return false;
  for (final e in d.listSync(followLinks: false)) {
    if (e is File) {
      final n = e.path.toLowerCase();
      if (LibraryScanner.videoExtensions.any((ext) => n.endsWith(ext))) return true;
    }
  }
  return false;
}

static String _parentPath(String path) {
  final norm = path.endsWith('/') || path.endsWith('\\')
      ? path.substring(0, path.length - 1) : path;
  final i = norm.lastIndexOf('/') > norm.lastIndexOf('\\')
      ? norm.lastIndexOf('/') : norm.lastIndexOf('\\');
  return i >= 0 ? norm.substring(0, i) : norm;
}
```

- [ ] **Step 4: 全量绿 + analyze** — `flutter test && flutter analyze`
- [ ] **Step 5: Commit** — `git commit -m "feat: episode/folder delete (trash+cascade), folder rename/reveal"`

---

### Task 4: 侧边栏 — 可折叠分组 + 文件夹菜单 + 文件删除 + 确认弹框

**Files:** Modify `lib/ui/episode_sidebar.dart`; Create `lib/ui/rename_folder_dialog.dart`, `lib/ui/confirm_dialog.dart`; Test `test/ui/episode_sidebar_test.dart`, `test/ui/rename_folder_dialog_test.dart`

**Interfaces:**
- `final expandedGroupsProvider = StateProvider<Set<String>>((ref) => {});`（存展开的 dirPath）
- `Future<bool> showConfirmDialog(BuildContext, {required String title, required String message});`
- `Future<void> showRenameFolderDialog(BuildContext, SeriesGroup group);`（预填目录名，确认调 `renameFolder`）

- [ ] **Step 1: 失败测试**（侧边栏）

```dart
  testWidgets('分组默认收起，正在播放的组自动展开', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [playerEngineProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    // two groups; playAt(0) makes group A current -> A expanded, B collapsed
    await container.read(playbackQueueProvider.notifier).loadSeries(Series(
      name: 'lib', rootPath: '/lib', groups: [
        SeriesGroup(title: 'A', dirPath: '/lib/A', episodes: [Episode(path:'/lib/A/1', fileName:'1', displayName:'A 01', episodeNumber:1)]),
        SeriesGroup(title: 'B', dirPath: '/lib/B', episodes: [Episode(path:'/lib/B/1', fileName:'1', displayName:'B 01', episodeNumber:1)]),
      ]));
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: Scaffold(body: EpisodeSidebar()))));
    await tester.pump();
    expect(find.text('A'), findsOneWidget); // header
    expect(find.text('B'), findsOneWidget); // header
    expect(find.text('A 01'), findsOneWidget); // A expanded (current)
    expect(find.text('B 01'), findsNothing);   // B collapsed
    // tap B header -> expands
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(find.text('B 01'), findsOneWidget);
  });

  testWidgets('组菜单有 打开所在位置/重命名/删除；文件菜单含 删除', (tester) async {
    final container = ProviderContainer(overrides: [playerEngineProvider.overrideWithValue(FakePlayerEngine())]);
    addTearDown(container.dispose);
    await container.read(playbackQueueProvider.notifier).loadSeries(Series(
      name: 'lib', rootPath: '/lib', groups: [
        SeriesGroup(title: 'A', dirPath: '/lib/A', episodes: [Episode(path:'/lib/A/1', fileName:'1', displayName:'A 01', episodeNumber:1)]),
      ]));
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: Scaffold(body: EpisodeSidebar()))));
    await tester.pump();
    // open folder menu (header trailing more)
    await tester.tap(find.byKey(const Key('folder-menu-/lib/A')));
    await tester.pumpAndSettle();
    expect(find.text('打开所在位置'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsWidgets);
    // (group A is current so expanded; open file menu)
    // dismiss menu then open episode menu
    await tester.tapAt(const Offset(5,5));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsWidgets);
  });
```

```dart
// test/ui/rename_folder_dialog_test.dart — 预填目录名、确认调 renameFolder
// 仿 rename_episode_dialog_test：用 _RecordingActions(noSuchMethod) 覆盖 libraryActionsProvider，
// showRenameFolderDialog(ctx, group)，预填 group 目录名（dirPath 的 basename），输入新名点确定，断言 renameFolder 调用。
```

- [ ] **Step 2: 确认失败** — FAIL。

- [ ] **Step 3: 实现 confirm_dialog.dart**

```dart
import 'package:flutter/material.dart';
Future<bool> showConfirmDialog(BuildContext context,
    {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
      ],
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 4: 实现 rename_folder_dialog.dart**（仿 rename_episode_dialog；预填 `_baseName(group.dirPath)`，确认 `ref.read(libraryActionsProvider).renameFolder(group, name)`，错误 SnackBar，成功 pop）

- [ ] **Step 5: 实现 episode_sidebar.dart 自绘可折叠分组**

要点：
- `final expanded = ref.watch(expandedGroupsProvider);`
- 遍历 groups，维护 `globalIndex`；对每组先判断 `containsCurrent`（该组任一全局下标 == currentIndex）。`isExpanded = expanded.contains(g.dirPath) || containsCurrent`。
- 组标题行：可点击切换（`onTap`：toggle dirPath in `expandedGroupsProvider`），含展开箭头图标 + 标题 + 末尾 `PopupMenuButton`（key `folder-menu-<dirPath>`，项：reveal→`revealFolder`、rename→`showRenameFolderDialog`、delete→确认后 `deleteFolder`）。对 `isRootGroup` 隐藏 rename/delete（只留 reveal）。
- 仅当 `isExpanded` 时渲染该组 episode 行（沿用现有 ListTile，trailing 菜单**加 delete**：delete→（可选确认）`deleteEpisode(ep)`）。
- `globalIndex` 始终自增（无论是否渲染），保证 `playAt(idx)` 正确。
- 删除文件夹/文件用 `showConfirmDialog`（文件夹必确认；文件删除可直接 trash，不强制确认）。注意 async gap：先 `final actions = ref.read(libraryActionsProvider);` 再 await。

- [ ] **Step 6: 全量绿 + analyze** — `flutter test && flutter analyze`
- [ ] **Step 7: Commit** — `git commit -m "feat: collapsible groups with folder/file delete-rename-reveal menus"`

---

## Self-Review
- 折叠默认收起+播放组自动展开 → T4（`isExpanded = expanded||containsCurrent`）。
- 文件夹 打开位置/重命名/删除 + 根目录护栏 → T3（方法+guard）、T4（菜单+隐藏）。
- 文件删除 + 级联删空文件夹 + 刷新 → T3（deleteEpisode/_dirHasVideo/_rescan）。
- 废纸篓 → T1（moveToTrash macOS Finder + 非 macOS 回退）。
- 类型一致：`FileSystemOps.moveToTrash/renameDirectory/trashCommand`、`SeriesGroup.dirPath`、`LibraryActions.deleteEpisode/renameFolder/deleteFolder/revealFolder/isRootGroup`、`expandedGroupsProvider`、`showConfirmDialog`、`showRenameFolderDialog` 跨任务签名一致。
- 依赖：`_parentPath` 在 library_actions 内新增（scanner 的是私有，不复用）；`videoExtensions` 用 `LibraryScanner.videoExtensions`（public static）。
