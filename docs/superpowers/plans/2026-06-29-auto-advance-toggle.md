# 自动连播开关（持久化）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 给"自动连播下一集"加一个可见、可持久化的开关（控制栏按钮，默认开）。行为：播完一集按列表顺序自动播下一集（含跨文件夹/跨剧），关掉后不自动连播。

**Architecture:** 新增 `autoAdvanceProvider`（StateNotifier<bool> + shared_preferences 持久化）；`playbackQueueProvider` 构建时把它同步到 `PlaybackQueueController.autoNext`（初始 + ref.listen）；控制栏加一枚切换按钮。

**Tech Stack:** Flutter、hooks_riverpod、shared_preferences。

## Global Constraints
- 设置键 `auto_advance_v1`，默认 `true`；无值返回 true。
- `PlaybackQueueController` 的完成连播逻辑沿用现有 `autoNext` 字段（按全局顺序 `state.hasNext` 连播，跨组）。不改连播算法，只让 `autoNext` 由设置驱动。
- 控制栏开关 tooltip：开=`自动连播：开`，关=`自动连播：关`；图标 `Icons.queue_play_next`，开=白、关=白38。
- 全程 `flutter test` 绿、`flutter analyze` 0 issue；每任务一次提交。

---

### Task 1: autoAdvance 设置 provider + 接线到 PlaybackQueue

**Files:**
- Create: `lib/state/playback_settings.dart`
- Modify: `lib/state/playback_queue.dart`（仅 provider 工厂处接线）
- Test: `test/state/playback_settings_test.dart`

**Interfaces:**
- `class AutoAdvanceController extends StateNotifier<bool> { Future<void> set(bool); Future<void> toggle(); }`
- `final autoAdvanceProvider = StateNotifierProvider<AutoAdvanceController, bool>(...)`

- [ ] **Step 1: 失败测试**

```dart
// test/state/playback_settings_test.dart
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
```

- [ ] **Step 2: 确认失败** — `flutter test test/state/playback_settings_test.dart` → FAIL（文件不存在）。

- [ ] **Step 3: 实现 provider**

```dart
// lib/state/playback_settings.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoAdvanceController extends StateNotifier<bool> {
  AutoAdvanceController() : super(true) {
    _load();
  }

  static const String _key = 'auto_advance_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final autoAdvanceProvider =
    StateNotifierProvider<AutoAdvanceController, bool>(
        (ref) => AutoAdvanceController());
```

- [ ] **Step 4: 接线 playbackQueueProvider**（仅改 provider 工厂；控制器类不动）

在 `lib/state/playback_queue.dart`：`import 'package:jump_player/state/playback_settings.dart';`，把 provider 工厂改为：

```dart
final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueController, PlaybackQueueState>((ref) {
  final engine = ref.watch(playerEngineProvider);
  final controller = PlaybackQueueController(engine);
  controller.autoNext = ref.read(autoAdvanceProvider);
  ref.listen<bool>(autoAdvanceProvider, (_, value) => controller.autoNext = value);
  return controller;
});
```

- [ ] **Step 5: 接线测试**（追加到 playback_settings_test.dart 或 playback_queue_test.dart）

```dart
  test('autoAdvanceProvider 同步到 PlaybackQueueController.autoNext', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      // engine override 用现有 FakePlayerEngine 模式
    ]);
    addTearDown(c.dispose);
    final controller = c.read(playbackQueueProvider.notifier);
    expect(controller.autoNext, isTrue);
    await c.read(autoAdvanceProvider.notifier).set(false);
    expect(controller.autoNext, isFalse);
  });
```
> 注：该测试需要 `playerEngineProvider.overrideWithValue(FakePlayerEngine())`（见现有 playback_queue_test 的 import/用法）。放在 playback_queue_test.dart 更合适，可复用其 imports。

- [ ] **Step 6: 全量绿 + analyze** — `flutter test && flutter analyze`
- [ ] **Step 7: Commit** — `git commit -m "feat: persistent auto-advance setting wired to playback queue"`

---

### Task 2: 控制栏自动连播开关

**Files:**
- Modify: `lib/ui/control_bar.dart`
- Test: `test/ui/control_bar_test.dart`

**Interfaces:** 控制栏在"下一集"之后、"命名配置"之前加一枚切换按钮。

- [ ] **Step 1: 失败测试**（追加到 control_bar_test.dart）

```dart
  testWidgets('控制栏有自动连播开关且可切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      windowControllerProvider.overrideWithValue(FakeWindowController()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ControlBar())),
    ));
    await tester.pump();

    expect(find.byTooltip('自动连播：开'), findsOneWidget);
    await tester.tap(find.byTooltip('自动连播：开'));
    await tester.pump();
    expect(container.read(autoAdvanceProvider), isFalse);
    expect(find.byTooltip('自动连播：关'), findsOneWidget);
  });
```
> 需 import `shared_preferences` 与 `playback_settings.dart`，并在文件已有 `TestWidgetsFlutterBinding.ensureInitialized()`（若无则在 main 顶部加）。

- [ ] **Step 2: 确认失败** — FAIL（找不到 tooltip）。

- [ ] **Step 3: 实现**

在 `lib/ui/control_bar.dart`：`import 'package:jump_player/state/playback_settings.dart';`，build 内 `final autoAdvance = ref.watch(autoAdvanceProvider);`，在"下一集" `IconButton` 之后插入：

```dart
          IconButton(
            tooltip: autoAdvance ? '自动连播：开' : '自动连播：关',
            color: autoAdvance ? Colors.white : Colors.white38,
            icon: const Icon(Icons.queue_play_next),
            onPressed: () => ref.read(autoAdvanceProvider.notifier).toggle(),
          ),
```

- [ ] **Step 4: 全量绿 + analyze** — `flutter test && flutter analyze`
- [ ] **Step 5: Commit** — `git commit -m "feat: control-bar auto-advance toggle"`

---

## Self-Review
- 开关持久化 → T1（AutoAdvanceController + shared_preferences）。
- 设置驱动连播 → T1（provider 工厂 ref.read + ref.listen 同步 autoNext；连播算法不变）。
- 控制栏可见开关 → T2。
- 类型一致：`autoAdvanceProvider`/`AutoAdvanceController.set/toggle`、`PlaybackQueueController.autoNext`（已存在）跨任务一致。
- 现有 playback_queue 单测构造 `PlaybackQueueController` 直接用，不受 provider 工厂改动影响（autoNext 默认 true 仍在）。
