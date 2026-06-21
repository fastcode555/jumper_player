# P2.5 底部控制栏 + 全屏 + Tooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** 把悬浮在画面中央的「打开文件/打开文件夹/播放暂停」按钮收进一条**底部控制栏**，加上「上一集/下一集/全屏」与每个按钮的 tooltip，不再遮挡视频画面。

**Architecture:** 新增 `WindowController` 抽象（domain，可 mock）封装全屏，`WindowManagerController`（infra，window_manager）为桌面实现。`ControlBar` widget 用 Riverpod 读取播放/队列/全屏状态。PlayerPage 改为「视频区 Expanded + 底部 ControlBar」的 Column 布局，移除中央悬浮按钮。

**Tech Stack:** Flutter, window_manager（新增，桌面全屏），hooks_riverpod, media_kit。

## Global Constraints
- write once；播放仍 media_kit。
- `lib/domain/` 纯 Dart；全屏通过 `WindowController` 抽象，桌面用 window_manager，移动端本期空实现，后续补 SystemChrome。
- 保留既有功能：打开文件、打开文件夹、播放/暂停、侧边栏、上一集/下一集、自动连播。
- 每个控制按钮包 `Tooltip`。
- TDD；每任务独立可测；频繁提交。

---

### Task 1: window_manager 依赖 + WindowController 抽象

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/domain/window/window_controller.dart`
- Create: `lib/state/window_providers.dart`
- Test: `test/domain/window/window_controller_test.dart`

**Produces:**
- `abstract class WindowController { Future<void> setFullScreen(bool value); Future<bool> isFullScreen(); }`
- `class FakeWindowController implements WindowController { bool fullScreen = false; ... }`
- `windowControllerProvider`（Provider，默认抛 UnimplementedError 直到 override）
- `isFullScreenProvider`（StateProvider<bool>，默认 false）

- [ ] **Step 1: 加依赖** — `pubspec.yaml` dependencies 加 `window_manager: ^0.4.2`，`flutter pub get`（解析失败则 `flutter pub add window_manager`）。

- [ ] **Step 2: 写失败测试** `test/domain/window/window_controller_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/window/window_controller.dart';

void main() {
  test('FakeWindowController toggles fullscreen', () async {
    final w = FakeWindowController();
    expect(await w.isFullScreen(), isFalse);
    await w.setFullScreen(true);
    expect(await w.isFullScreen(), isTrue);
    expect(w.fullScreen, isTrue);
  });
}
```

- [ ] **Step 3: 运行确认 RED** — `flutter test test/domain/window/window_controller_test.dart` → FAIL。

- [ ] **Step 4: 写实现**

`lib/domain/window/window_controller.dart`:
```dart
abstract class WindowController {
  Future<void> setFullScreen(bool value);
  Future<bool> isFullScreen();
}

class FakeWindowController implements WindowController {
  bool fullScreen = false;

  @override
  Future<void> setFullScreen(bool value) async {
    fullScreen = value;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;
}
```

`lib/state/window_providers.dart`:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/window/window_controller.dart';

final windowControllerProvider = Provider<WindowController>((ref) {
  throw UnimplementedError('windowControllerProvider must be overridden at startup');
});

final isFullScreenProvider = StateProvider<bool>((ref) => false);
```

- [ ] **Step 5: GREEN + analyze** — `flutter test test/domain/window/window_controller_test.dart && flutter analyze` → PASS / 无 error。

- [ ] **Step 6: 提交**
```bash
git add pubspec.yaml pubspec.lock lib/domain/window/window_controller.dart lib/state/window_providers.dart test/domain/window/window_controller_test.dart
git commit -m "feat: add window_manager dep and WindowController abstraction"
```

---

### Task 2: WindowManagerController 实现 + main 初始化

**Files:**
- Create: `lib/infra/window/window_manager_controller.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 写实现** `lib/infra/window/window_manager_controller.dart`:
```dart
import 'package:window_manager/window_manager.dart';
import 'package:jump_player/domain/window/window_controller.dart';

class WindowManagerController implements WindowController {
  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();
}
```

- [ ] **Step 2: main 初始化并 override** `lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:jump_player/app.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/domain/window/window_controller.dart';
import 'package:jump_player/infra/playback/media_kit_player_engine.dart';
import 'package:jump_player/infra/window/window_manager_controller.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/window_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  final PlayerEngine engine = MediaKitPlayerEngine();
  final WindowController window = WindowManagerController();
  runApp(
    ProviderScope(
      overrides: [
        playerEngineProvider.overrideWithValue(engine),
        windowControllerProvider.overrideWithValue(window),
      ],
      child: const JumpPlayerApp(),
    ),
  );
}
```

- [ ] **Step 3: analyze** — `flutter analyze` → 无 error。（无单测：window_manager 是原生封装，契约由 FakeWindowController 覆盖。）

- [ ] **Step 4: 提交**
```bash
git add lib/infra/window/window_manager_controller.dart lib/main.dart
git commit -m "feat: wire WindowManagerController for desktop fullscreen"
```

---

### Task 3: ControlBar 控制栏 + PlayerPage 布局重构

**Files:**
- Create: `lib/ui/control_bar.dart`
- Modify: `lib/ui/player_page.dart`
- Test: `test/ui/control_bar_test.dart`，Modify: `test/ui/player_page_test.dart`

- [ ] **Step 1: 写失败 widget 测试** `test/ui/control_bar_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/domain/window/window_controller.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/window_providers.dart';
import 'package:jump_player/ui/control_bar.dart';

void main() {
  testWidgets('shows tooltipped controls and toggles fullscreen', (tester) async {
    final fakeWin = FakeWindowController();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      windowControllerProvider.overrideWithValue(fakeWin),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ControlBar())),
      ),
    );

    expect(find.byTooltip('打开文件'), findsOneWidget);
    expect(find.byTooltip('打开文件夹'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);

    await tester.tap(find.byTooltip('全屏'));
    await tester.pump();
    expect(container.read(isFullScreenProvider), isTrue);
    expect(fakeWin.fullScreen, isTrue);
  });
}
```

- [ ] **Step 2: 运行确认 RED** — `flutter test test/ui/control_bar_test.dart` → FAIL。

- [ ] **Step 3: 写 ControlBar** `lib/ui/control_bar.dart`:
```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/window_providers.dart';

class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playerEngineProvider);
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final queue = ref.watch(playbackQueueProvider);
    final isFullScreen = ref.watch(isFullScreenProvider);

    return Container(
      height: 56,
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '打开文件',
            color: Colors.white,
            icon: const Icon(Icons.insert_drive_file_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final result =
                  await FilePicker.platform.pickFiles(type: FileType.video);
              if (result == null || result.files.isEmpty) return;
              final path = result.files.first.path;
              if (path == null) return;
              try {
                await engine.open(path);
                await engine.play();
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('无法播放该文件：$e')),
                );
              }
            },
          ),
          IconButton(
            tooltip: '打开文件夹',
            color: Colors.white,
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final path = await FilePicker.platform.getDirectoryPath();
              if (path == null) return;
              try {
                await ref.read(libraryActionsProvider).openFolder(path);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('无法扫描该文件夹：$e')),
                );
              }
            },
          ),
          IconButton(
            tooltip: '上一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
            onPressed: queue.hasPrevious
                ? ref.read(playbackQueueProvider.notifier).previous
                : null,
          ),
          IconButton(
            tooltip: isPlaying ? '暂停' : '播放',
            color: Colors.white,
            iconSize: 36,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () async {
              isPlaying ? await engine.pause() : await engine.play();
            },
          ),
          IconButton(
            tooltip: '下一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
            onPressed: queue.hasNext
                ? ref.read(playbackQueueProvider.notifier).next
                : null,
          ),
          IconButton(
            tooltip: '全屏',
            color: Colors.white,
            icon: Icon(isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: () async {
              final next = !isFullScreen;
              await ref.read(windowControllerProvider).setFullScreen(next);
              ref.read(isFullScreenProvider.notifier).state = next;
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: GREEN** — `flutter test test/ui/control_bar_test.dart` → PASS。

- [ ] **Step 5: 重构 PlayerPage 布局** — `lib/ui/player_page.dart` 的 `build` 返回结构改为视频/侧边栏放 `Expanded` 的 `Stack`，底部接 `ControlBar`，**移除原居中的「打开文件/打开文件夹/播放暂停」按钮 Column**。import `control_bar.dart`。结构：
```dart
return Scaffold(
  backgroundColor: Colors.black,
  body: Column(
    children: [
      Expanded(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null) Video(controller: controller),
            if (ref.watch(sidebarVisibleProvider))
              const Align(
                alignment: Alignment.centerRight,
                child: EpisodeSidebar(),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: '剧集列表',
                color: Colors.white,
                icon: const Icon(Icons.playlist_play),
                onPressed: () =>
                    ref.read(sidebarVisibleProvider.notifier).state =
                        !ref.read(sidebarVisibleProvider),
              ),
            ),
          ],
        ),
      ),
      const ControlBar(),
    ],
  ),
);
```
保留 `final controller = ref.watch(videoControllerProvider);`。PlayerPage 内不再使用的 provider（如 playerEngineProvider/isPlayingProvider）按 `flutter analyze` 提示清理未用引用。

- [ ] **Step 6: 调整既有 player_page widget 测试** — 原 `test/ui/player_page_test.dart` 断言 `find.text('打开文件')`；现按钮变为带 tooltip 的图标，文本不存在。把该断言改为 `expect(find.byType(ControlBar), findsOneWidget);`（import control_bar.dart）。这是 UI 重构必要的测试调整，仍验证页面渲染控制栏，非削弱。

- [ ] **Step 7: 全套 + analyze** — `flutter test && flutter analyze` → 全 PASS / 无 error。

- [ ] **Step 8: 提交**
```bash
git add lib/ui/control_bar.dart lib/ui/player_page.dart test/ui/control_bar_test.dart test/ui/player_page_test.dart
git commit -m "feat: bottom control bar with tooltips + fullscreen; remove floating buttons"
```

---

### Task 4: 冒烟 + 文档

**Files:** Modify: `docs/RUNNING.md`

- [ ] **Step 1: 全套 + analyze** — `flutter test && flutter analyze` → 全 PASS / 无 error。
- [ ] **Step 2: 追加 P2.5 冒烟清单** 到 `docs/RUNNING.md`：①底部控制栏含 打开文件/打开文件夹/上一集/播放暂停/下一集/全屏，悬停显 tooltip；②画面中央不再有悬浮按钮；③全屏可进可退、图标切换；④各按钮功能正常。
- [ ] **Step 3: 提交**
```bash
git add docs/RUNNING.md
git commit -m "docs: add P2.5 control-bar smoke checklist"
```

---

## Self-Review
**Spec coverage:** 控制栏含全部要求按钮 + tooltip（用户诉求②），全屏经 WindowController 抽象（桌面 window_manager）；中央悬浮按钮移除。**Placeholder scan:** 无占位符。**Type consistency:** `WindowController.setFullScreen/isFullScreen`、`windowControllerProvider`、`isFullScreenProvider`、`ControlBar` 跨任务一致；复用既有 `playbackQueueProvider`/`libraryActionsProvider`/`isPlayingProvider`/`sidebarVisibleProvider`。
