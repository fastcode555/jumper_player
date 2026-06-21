# P1 基础骨架 + 基本播放 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭起 Flutter 五端工程骨架，集成 media_kit（libmpv），实现"选一个本地视频文件并在窗口内播放"的最小可用垂直切片。

**Architecture:** Flutter 单一代码库 + media_kit 作为播放引擎。领域层用纯 Dart 的 `PlaybackController` 封装播放状态（可注入 mock 的 `Player` 抽象，便于单测）；UI 层用 Riverpod 暴露状态。本计划只覆盖单文件播放，不含媒体库/扫描（P2）。

**Tech Stack:** Flutter, media_kit + media_kit_video, Riverpod (hooks_riverpod), file_picker, flutter_test。

## Global Constraints

- 目标平台：macOS / Linux / Windows / Android / iOS，单一代码库 write once。
- 播放引擎必须是 media_kit（libmpv 后端），**禁止**使用 Flutter 自带 `video_player`（格式兼容差）。
- 领域服务层（`lib/domain/`）为纯 Dart，**不得** import `package:flutter/*` 之外无关的平台代码，必须可在 `flutter test` 下无设备运行。
- 状态管理统一用 Riverpod。
- 每个任务以一个独立可测的交付物结束，遵循 TDD，频繁提交。

---

### Task 1: 初始化 Flutter 工程与版本管理

**Files:**
- Create: 整个 Flutter 工程骨架（`pubspec.yaml`, `lib/main.dart`, 各端 runner 目录）
- Create: `.gitignore`

**Interfaces:**
- Consumes: 无
- Produces: 可编译运行的空 Flutter app；`flutter test` 可执行。

- [ ] **Step 1: 创建工程**

Run:
```bash
cd /Users/barry/Code/github/jump_player
flutter create --org com.jumpplayer --project-name jump_player --platforms=macos,linux,windows,android,ios .
```

- [ ] **Step 2: 初始化 git 并首次提交**

Run:
```bash
git init
git add -A
git commit -m "chore: scaffold flutter project for 5 platforms"
```

- [ ] **Step 3: 验证默认测试通过**

Run: `flutter test`
Expected: PASS（Flutter 默认生成的 `test/widget_test.dart` 通过）

- [ ] **Step 4: 删除默认 counter 示例的 widget 测试占位**

删除 `test/widget_test.dart`（其断言基于默认 counter UI，后续会替换）。

Run: `git rm test/widget_test.dart && git commit -m "chore: remove default counter widget test"`

---

### Task 2: 加入依赖

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: 无
- Produces: 项目可用 `media_kit`, `media_kit_video`, `hooks_riverpod`, `file_picker`。

- [ ] **Step 1: 添加依赖到 pubspec.yaml**

在 `dependencies:` 下加入（版本以当前 pub.dev 最新稳定版为准，写入精确下限）：
```yaml
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_video: ^1.0.4
  hooks_riverpod: ^2.5.1
  flutter_hooks: ^0.20.5
  file_picker: ^8.0.0
```

- [ ] **Step 2: 拉取依赖**

Run: `flutter pub get`
Expected: 成功解析，无版本冲突。

- [ ] **Step 3: 提交**

Run:
```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add media_kit, riverpod, file_picker dependencies"
```

---

### Task 3: 定义播放引擎抽象（可 mock 的纯 Dart 接口）

**Files:**
- Create: `lib/domain/playback/player_engine.dart`
- Test: `test/domain/playback/player_engine_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `abstract class PlayerEngine` 含方法：
    - `Future<void> open(String filePath)`
    - `Future<void> play()`
    - `Future<void> pause()`
    - `Future<void> seek(Duration position)`
    - `Stream<Duration> get positionStream`
    - `Stream<bool> get playingStream`
    - `Future<void> dispose()`
  - `class FakePlayerEngine implements PlayerEngine`（测试与早期 UI 用，记录调用、可手动推流）。

- [ ] **Step 1: 写失败测试**

`test/domain/playback/player_engine_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

void main() {
  group('FakePlayerEngine', () {
    test('open records the opened path', () async {
      final engine = FakePlayerEngine();
      await engine.open('/movies/ep01.mkv');
      expect(engine.openedPath, '/movies/ep01.mkv');
    });

    test('play and pause emit on playingStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <bool>[];
      final sub = engine.playingStream.listen(emitted.add);
      await engine.play();
      await engine.pause();
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [true, false]);
      await sub.cancel();
    });

    test('seek pushes position onto positionStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <Duration>[];
      final sub = engine.positionStream.listen(emitted.add);
      await engine.seek(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [const Duration(seconds: 42)]);
      await sub.cancel();
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/playback/player_engine_test.dart`
Expected: FAIL（`player_engine.dart` 不存在 / 类型未定义）

- [ ] **Step 3: 写最小实现**

`lib/domain/playback/player_engine.dart`:
```dart
import 'dart:async';

abstract class PlayerEngine {
  Future<void> open(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Future<void> dispose();
}

class FakePlayerEngine implements PlayerEngine {
  String? openedPath;
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  @override
  Future<void> open(String filePath) async {
    openedPath = filePath;
  }

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> pause() async => _playing.add(false);

  @override
  Future<void> seek(Duration position) async => _position.add(position);

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/domain/playback/player_engine_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

Run:
```bash
git add lib/domain/playback/player_engine.dart test/domain/playback/player_engine_test.dart
git commit -m "feat: add PlayerEngine abstraction with FakePlayerEngine"
```

---

### Task 4: media_kit 适配实现 `MediaKitPlayerEngine`

**Files:**
- Create: `lib/infra/playback/media_kit_player_engine.dart`
- Modify: `lib/main.dart`（在 `main()` 调用 `MediaKit.ensureInitialized()`）

**Interfaces:**
- Consumes: `PlayerEngine`（Task 3）
- Produces: `class MediaKitPlayerEngine implements PlayerEngine`，内部持有 `media_kit` 的 `Player`，并暴露 `Player get raw`（供 `Video` widget 用 `VideoController`）。

- [ ] **Step 1: 实现适配类**

`lib/infra/playback/media_kit_player_engine.dart`:
```dart
import 'package:media_kit/media_kit.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine() : _player = Player();

  final Player _player;

  Player get raw => _player;

  @override
  Future<void> open(String filePath) =>
      _player.open(Media(filePath), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Future<void> dispose() => _player.dispose();
}
```

- [ ] **Step 2: 在 main 初始化 MediaKit**

`lib/main.dart` 顶部 `main()` 改为：
```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:jump_player/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: JumpPlayerApp()));
}
```

> 说明：`app.dart`（`JumpPlayerApp`）在 Task 6 创建。本步骤先建 `main.dart`，若此时 `flutter analyze` 报 `app.dart` 缺失属于预期，Task 6 补齐。

- [ ] **Step 3: 验证编译（分析）**

Run: `flutter analyze lib/infra/playback/media_kit_player_engine.dart`
Expected: 该文件无 error（仅可能有未使用提示）。

- [ ] **Step 4: 提交**

Run:
```bash
git add lib/infra/playback/media_kit_player_engine.dart lib/main.dart
git commit -m "feat: add MediaKitPlayerEngine adapter and init MediaKit in main"
```

---

### Task 5: Riverpod 播放状态 Provider

**Files:**
- Create: `lib/state/playback_providers.dart`
- Test: `test/state/playback_providers_test.dart`

**Interfaces:**
- Consumes: `PlayerEngine`, `FakePlayerEngine`（Task 3）
- Produces:
  - `final playerEngineProvider = Provider<PlayerEngine>(...)`（默认抛错，需在 app 入口 override 为真实实现；测试 override 为 fake）
  - `final isPlayingProvider = StreamProvider<bool>(...)`（来自 `playerEngineProvider.playingStream`）
  - `final positionProvider = StreamProvider<Duration>(...)`

- [ ] **Step 1: 写失败测试**

`test/state/playback_providers_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

void main() {
  test('isPlayingProvider reflects engine play()', () async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final sub = container.listen(isPlayingProvider, (_, __) {});
    await fake.play();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(isPlayingProvider).value, true);
    sub.close();
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/state/playback_providers_test.dart`
Expected: FAIL（`playback_providers.dart` 不存在）

- [ ] **Step 3: 写最小实现**

`lib/state/playback_providers.dart`:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

final playerEngineProvider = Provider<PlayerEngine>((ref) {
  throw UnimplementedError(
    'playerEngineProvider must be overridden at app startup',
  );
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playerEngineProvider).playingStream;
});

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playerEngineProvider).positionStream;
});
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/state/playback_providers_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

Run:
```bash
git add lib/state/playback_providers.dart test/state/playback_providers_test.dart
git commit -m "feat: add Riverpod playback providers"
```

---

### Task 6: 播放页 UI + 选文件 + App 入口

**Files:**
- Create: `lib/app.dart`
- Create: `lib/ui/player_page.dart`
- Modify: `lib/main.dart`（override `playerEngineProvider` 为 `MediaKitPlayerEngine`）
- Test: `test/ui/player_page_test.dart`

**Interfaces:**
- Consumes: `playerEngineProvider`, `isPlayingProvider`（Task 5）；`MediaKitPlayerEngine`（Task 4）；`file_picker`。
- Produces: `class JumpPlayerApp`、`class PlayerPage`；UI 含"打开文件"按钮（调用 `FilePicker.platform.pickFiles`）与播放/暂停按钮。

- [ ] **Step 1: 写失败的 widget 测试**

`test/ui/player_page_test.dart`（用 fake engine，不依赖真实视频/native）:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/ui/player_page.dart';

void main() {
  testWidgets('shows Open File button initially', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerEngineProvider.overrideWithValue(FakePlayerEngine())],
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    expect(find.text('打开文件'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/player_page_test.dart`
Expected: FAIL（`player_page.dart` 不存在）

- [ ] **Step 3: 写 PlayerPage 实现**

`lib/ui/player_page.dart`:
```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playerEngineProvider);
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.video,
                );
                final path = result?.files.single.path;
                if (path != null) {
                  await engine.open(path);
                  await engine.play();
                }
              },
              child: const Text('打开文件'),
            ),
            IconButton(
              color: Colors.white,
              iconSize: 48,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  isPlaying ? engine.pause() : engine.play(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 写 App 入口**

`lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:jump_player/ui/player_page.dart';

class JumpPlayerApp extends StatelessWidget {
  const JumpPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jump Player',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerPage(),
    );
  }
}
```

- [ ] **Step 5: main.dart override 真实引擎**

`lib/main.dart` 改为：
```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:jump_player/app.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/infra/playback/media_kit_player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final PlayerEngine engine = MediaKitPlayerEngine();
  runApp(
    ProviderScope(
      overrides: [playerEngineProvider.overrideWithValue(engine)],
      child: const JumpPlayerApp(),
    ),
  );
}
```

- [ ] **Step 6: 运行 widget 测试确认通过**

Run: `flutter test test/ui/player_page_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

Run:
```bash
git add lib/app.dart lib/ui/player_page.dart lib/main.dart test/ui/player_page_test.dart
git commit -m "feat: add player page with open-file and play/pause"
```

---

### Task 7: 接入实际视频渲染面 `Video` widget

**Files:**
- Modify: `lib/infra/playback/media_kit_player_engine.dart`（暴露 `VideoController`）
- Modify: `lib/ui/player_page.dart`（用 `Video` 渲染）
- Modify: `lib/state/playback_providers.dart`（暴露 `videoControllerProvider`）

**Interfaces:**
- Consumes: `MediaKitPlayerEngine.raw`（Task 4）
- Produces: `MediaKitPlayerEngine.videoController` (`VideoController`)；`videoControllerProvider`（仅在真实引擎下可用，fake 下返回 null）。

- [ ] **Step 1: 在适配类暴露 VideoController**

在 `MediaKitPlayerEngine` 中加：
```dart
import 'package:media_kit_video/media_kit_video.dart';
// ...
late final VideoController videoController = VideoController(_player);
```

- [ ] **Step 2: provider 暴露可空 controller**

`lib/state/playback_providers.dart` 增加：
```dart
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jump_player/infra/playback/media_kit_player_engine.dart';

final videoControllerProvider = Provider<VideoController?>((ref) {
  final engine = ref.watch(playerEngineProvider);
  return engine is MediaKitPlayerEngine ? engine.videoController : null;
});
```

- [ ] **Step 3: PlayerPage 用 Video 渲染**

在 `PlayerPage.build` 中，将正中央 `Column` 包到一个 `Stack` 里，底层加视频面：
```dart
final controller = ref.watch(videoControllerProvider);
// body:
Stack(
  fit: StackFit.expand,
  children: [
    if (controller != null) Video(controller: controller),
    // 原有的 Center(child: Column(...)) 控制层放在上面
  ],
)
```
（导入 `package:media_kit_video/media_kit_video.dart`。控制层在 fake 引擎/widget 测试下因 controller 为 null 而不渲染 `Video`，测试仍通过。）

- [ ] **Step 4: 运行已有测试确认未破坏**

Run: `flutter test`
Expected: PASS（全部既有测试通过，`controller` 为 null 时不渲染 `Video`）

- [ ] **Step 5: 提交**

Run:
```bash
git add lib/infra/playback/media_kit_player_engine.dart lib/ui/player_page.dart lib/state/playback_providers.dart
git commit -m "feat: render actual video surface via media_kit Video widget"
```

---

### Task 8: 端到端冒烟（手动验证 + 文档）

**Files:**
- Create: `docs/RUNNING.md`

**Interfaces:**
- Consumes: 全部
- Produces: 手动验证步骤文档。

- [ ] **Step 1: 桌面端手动跑通**

Run（在 macOS 上）: `flutter run -d macos`
手动验证：点"打开文件"选一个本地 `.mkv`/`.mp4` → 视频开始播放 → 播放/暂停按钮可切换。

- [ ] **Step 2: 记录运行方式**

`docs/RUNNING.md` 写明各端运行命令（`flutter run -d macos|linux|windows`、Android/iOS 需连真机或模拟器），以及 media_kit 各端的系统依赖说明链接。

- [ ] **Step 3: 全量测试 + analyze**

Run: `flutter test && flutter analyze`
Expected: 测试全 PASS；analyze 无 error。

- [ ] **Step 4: 提交**

Run:
```bash
git add docs/RUNNING.md
git commit -m "docs: add running instructions and P1 smoke checklist"
```

---

## Self-Review

**1. Spec coverage（针对 P1 范围）:** P1 只承担 spec 第 2 节技术栈落地 + 第 5 节"基本播放"的最小切片（开文件、播放、暂停、视频渲染）。媒体库/扫描（第 4 节）、片头片尾（第 6 节）、截图/GIF（第 7 节）、沉浸式 UI（第 8 节）、存储（第 9 节）分别留给 P2–P5，符合分计划决策。无遗漏。

**2. Placeholder scan:** 无 TBD/TODO；每个代码步骤都给了完整代码与确切命令。Task 4 Step 2 引用的 `app.dart` 在 Task 6 创建，已在原步骤显式说明该顺序依赖。

**3. Type consistency:** `PlayerEngine` 方法签名（`open/play/pause/seek/positionStream/playingStream/dispose`）在 Task 3 定义，Task 4 的 `MediaKitPlayerEngine`、Task 5 provider、Task 6/7 UI 全部一致引用。`playerEngineProvider`/`isPlayingProvider`/`positionProvider`/`videoControllerProvider` 命名跨任务统一。
