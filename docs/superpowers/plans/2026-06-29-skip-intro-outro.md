# 跳过片头/片尾（同剧集）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 按剧目录配置片头/片尾秒数，对该剧所有集自动生效：每集开始自动 seek 跳过片头，播到末尾片尾区自动跳下一集（仅在自动连播开启时）；底部常驻设置条支持「标记当前位置」与「手填秒数」，持久化。

**Architecture:** 新增 `SkipConfig` 域模型 + shared_preferences 持久化 map（dirPath→SkipConfig）；给 `PlayerEngine` 加 `durationStream`；一个监听播放位置的 `SkipWatcher`（读当前剧配置/时长/自动连播开关，按位置自动 seek 片头、片尾跳下一集，每集一次性）；底部 `SkipSettingsBar` 编辑当前剧配置。

**Tech Stack:** Flutter、hooks_riverpod、shared_preferences、media_kit。

## Global Constraints
- 片头/片尾按"距边缘秒数"存（intro=从头 N 秒，outro=末尾 M 秒），0=不跳。
- 配置键 = 剧目录 `group.dirPath`；持久化 shared_preferences 键 `skip_config_v1`（JSON 对象 dirPath→{intro,outro}）；坏 JSON 回退空 map。
- 自动跳：片头每集到点 seek 一次；片尾每集到点触发一次，**仅当 `autoAdvanceProvider` 为真时**调 `queue.next()`。
- 一次性标记按 `currentEpisode.path`，切集自动重置。
- 时长未知(0)时片尾不触发；`introSeconds >= duration` 时不跳片头（防越界）。
- 设置 UI = 底部常驻条（ControlBar 下方），无当前播放集时隐藏。
- 全程 `flutter test` 绿、`flutter analyze` 0 issue；每任务一次提交。

---

### Task 1: SkipConfig 域模型

**Files:** Create `lib/domain/playback/skip_config.dart`; Test `test/domain/playback/skip_config_test.dart`

**Interfaces:**
- Produces: `class SkipConfig { const SkipConfig({int introSeconds=0,int outroSeconds=0}); final int introSeconds, outroSeconds; SkipConfig copyWith({int? introSeconds,int? outroSeconds}); Map<String,dynamic> toJson(); factory SkipConfig.fromJson(Map<String,dynamic>); == / hashCode; }`

- [ ] **Step 1: 失败测试**

```dart
// test/domain/playback/skip_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/playback/skip_config.dart';

void main() {
  test('默认 0/0', () {
    const c = SkipConfig();
    expect(c.introSeconds, 0);
    expect(c.outroSeconds, 0);
  });
  test('copyWith 只改指定字段', () {
    const c = SkipConfig(introSeconds: 90, outroSeconds: 60);
    expect(c.copyWith(introSeconds: 30), const SkipConfig(introSeconds: 30, outroSeconds: 60));
  });
  test('toJson/fromJson 往返', () {
    const c = SkipConfig(introSeconds: 90, outroSeconds: 60);
    expect(SkipConfig.fromJson(c.toJson()), c);
  });
  test('fromJson 缺字段回退 0', () {
    expect(SkipConfig.fromJson(const {}), const SkipConfig());
  });
}
```

- [ ] **Step 2: 跑测试确认失败** — `flutter test test/domain/playback/skip_config_test.dart` → FAIL（文件不存在）。

- [ ] **Step 3: 实现**

```dart
// lib/domain/playback/skip_config.dart
class SkipConfig {
  const SkipConfig({this.introSeconds = 0, this.outroSeconds = 0});

  final int introSeconds;
  final int outroSeconds;

  SkipConfig copyWith({int? introSeconds, int? outroSeconds}) => SkipConfig(
        introSeconds: introSeconds ?? this.introSeconds,
        outroSeconds: outroSeconds ?? this.outroSeconds,
      );

  Map<String, dynamic> toJson() =>
      {'intro': introSeconds, 'outro': outroSeconds};

  factory SkipConfig.fromJson(Map<String, dynamic> json) => SkipConfig(
        introSeconds: (json['intro'] as num?)?.toInt() ?? 0,
        outroSeconds: (json['outro'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is SkipConfig &&
      other.introSeconds == introSeconds &&
      other.outroSeconds == outroSeconds;

  @override
  int get hashCode => Object.hash(introSeconds, outroSeconds);
}
```

- [ ] **Step 4: 跑测试确认通过** — PASS。
- [ ] **Step 5: Commit** — `git commit -m "feat: SkipConfig model for per-series skip"`

---

### Task 2: PlayerEngine 时长流 + durationProvider

**Files:** Modify `lib/domain/playback/player_engine.dart`、`lib/infra/playback/media_kit_player_engine.dart`、`lib/state/playback_providers.dart`; Test `test/domain/playback/player_engine_test.dart`

**Interfaces:**
- Produces: `PlayerEngine.durationStream` (Stream<Duration>); `FakePlayerEngine` 新增 `emitDuration(Duration)`、`emitPosition(Duration)`、`Duration? seekedTo`；`durationProvider` (StreamProvider<Duration>)。

- [ ] **Step 1: 失败测试**（追加到 player_engine_test.dart）

```dart
  test('FakePlayerEngine emitDuration pushes onto durationStream', () async {
    final e = FakePlayerEngine();
    addTearDown(e.dispose);
    final f = expectLater(e.durationStream, emits(const Duration(minutes: 24)));
    e.emitDuration(const Duration(minutes: 24));
    await f;
  });
  test('FakePlayerEngine records seekedTo', () async {
    final e = FakePlayerEngine();
    addTearDown(e.dispose);
    await e.seek(const Duration(seconds: 90));
    expect(e.seekedTo, const Duration(seconds: 90));
  });
```

- [ ] **Step 2: 确认失败** — `flutter test test/domain/playback/player_engine_test.dart` → FAIL。

- [ ] **Step 3: 实现接口 + Fake**

在 `lib/domain/playback/player_engine.dart` 抽象类加：`Stream<Duration> get durationStream;`
在 `FakePlayerEngine`：
```dart
  final _duration = StreamController<Duration>.broadcast();
  Duration? seekedTo;
  // ...
  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    _position.add(position);
  }
  @override
  Stream<Duration> get durationStream => _duration.stream;
  void emitDuration(Duration d) => _duration.add(d);
  void emitPosition(Duration p) => _position.add(p);
  // 在 dispose() 里追加：await _duration.close();
```

- [ ] **Step 4: 实现 MediaKit + provider**

`lib/infra/playback/media_kit_player_engine.dart` 加：
```dart
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
```
`lib/state/playback_providers.dart` 加：
```dart
final durationProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playerEngineProvider).durationStream;
});
```

- [ ] **Step 5: 跑全量 + analyze** — `flutter test && flutter analyze` 全绿。
- [ ] **Step 6: Commit** — `git commit -m "feat: expose player durationStream + durationProvider"`

---

### Task 3: 持久化 store + skipConfigProvider + 当前组 dirPath

**Files:** Create `lib/infra/config/preferences_skip_store.dart`、`lib/state/skip_providers.dart`; Modify `lib/state/playback_queue.dart`(加 getter); Test `test/infra/config/preferences_skip_store_test.dart`、`test/state/skip_providers_test.dart`、`test/state/playback_queue_test.dart`(getter)

**Interfaces:**
- Consumes: `SkipConfig`（T1）
- Produces:
  - `PreferencesSkipStore { Future<Map<String,SkipConfig>> load(); Future<void> save(Map<String,SkipConfig>); }`
  - `skipConfigProvider` (StateNotifierProvider<SkipConfigController, Map<String,SkipConfig>>) with `SkipConfig configFor(String)`, `Future<void> setIntro(String,int)`, `setOutro(String,int)`, `clear(String)`.
  - `PlaybackQueueState.currentGroupDirPath` (String?)

- [ ] **Step 1: 失败测试（store）**

```dart
// test/infra/config/preferences_skip_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/infra/config/preferences_skip_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('无值返回空 map', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PreferencesSkipStore().load(), isEmpty);
  });
  test('save/load 往返', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesSkipStore();
    await store.save({'/a': const SkipConfig(introSeconds: 90, outroSeconds: 60)});
    final back = await store.load();
    expect(back['/a'], const SkipConfig(introSeconds: 90, outroSeconds: 60));
  });
  test('坏 JSON 回退空 map', () async {
    SharedPreferences.setMockInitialValues({'skip_config_v1': 'not json'});
    expect(await PreferencesSkipStore().load(), isEmpty);
  });
}
```

- [ ] **Step 2: 确认失败** — FAIL。

- [ ] **Step 3: 实现 store**

```dart
// lib/infra/config/preferences_skip_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';

class PreferencesSkipStore {
  static const String _key = 'skip_config_v1';

  Future<Map<String, SkipConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, SkipConfig.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, SkipConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final map = configs.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_key, jsonEncode(map));
  }
}
```

- [ ] **Step 4: 失败测试（provider + getter）**

```dart
// test/state/skip_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/state/skip_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('setIntro/setOutro 更新并持久化；configFor 默认 0', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(skipConfigProvider.notifier);
    expect(n.configFor('/a'), const SkipConfig());
    await n.setIntro('/a', 90);
    await n.setOutro('/a', 60);
    expect(n.configFor('/a'), const SkipConfig(introSeconds: 90, outroSeconds: 60));

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(skipConfigProvider); // 触发懒加载
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c2.read(skipConfigProvider.notifier).configFor('/a'),
        const SkipConfig(introSeconds: 90, outroSeconds: 60));
  });
}
```

加 getter 测试到 `test/state/playback_queue_test.dart`：
```dart
  test('currentGroupDirPath 定位当前集所在组', () async {
    // 用现有 FakePlayerEngine + ProviderContainer 载入含两组的 Series：
    //   g1 dirPath '/x/A' [e0], g2 dirPath '/x/B' [e1,e2]
    // playAt(2) -> currentGroupDirPath == '/x/B'; playAt(0) -> '/x/A'
    // （构造 Series/SeriesGroup 需带 dirPath；沿用文件已有 import）
  });
```
> 实施者：用 `Series(name:'x',rootPath:'/x',groups:[SeriesGroup(title:'A',dirPath:'/x/A',episodes:[ep0]),SeriesGroup(title:'B',dirPath:'/x/B',episodes:[ep1,ep2])])`，`loadSeries` 后 `playAt(2)`，断言 `container.read(playbackQueueProvider).currentGroupDirPath=='/x/B'`，写真实断言。

- [ ] **Step 5: 确认失败** — FAIL。

- [ ] **Step 6: 实现 provider + getter**

```dart
// lib/state/skip_providers.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/infra/config/preferences_skip_store.dart';

final skipStoreProvider =
    Provider<PreferencesSkipStore>((ref) => PreferencesSkipStore());

class SkipConfigController extends StateNotifier<Map<String, SkipConfig>> {
  SkipConfigController(this._store) : super(const {}) {
    _load();
  }
  final PreferencesSkipStore _store;

  Future<void> _load() async {
    final loaded = await _store.load();
    if (mounted) state = loaded;
  }

  SkipConfig configFor(String dirPath) => state[dirPath] ?? const SkipConfig();

  Future<void> setIntro(String dirPath, int seconds) => _update(
      dirPath, configFor(dirPath).copyWith(introSeconds: seconds < 0 ? 0 : seconds));

  Future<void> setOutro(String dirPath, int seconds) => _update(
      dirPath, configFor(dirPath).copyWith(outroSeconds: seconds < 0 ? 0 : seconds));

  Future<void> clear(String dirPath) async {
    final copy = Map<String, SkipConfig>.from(state)..remove(dirPath);
    state = copy;
    await _store.save(copy);
  }

  Future<void> _update(String dirPath, SkipConfig cfg) async {
    final copy = Map<String, SkipConfig>.from(state)..[dirPath] = cfg;
    state = copy;
    await _store.save(copy);
  }
}

final skipConfigProvider =
    StateNotifierProvider<SkipConfigController, Map<String, SkipConfig>>(
        (ref) => SkipConfigController(ref.watch(skipStoreProvider)));
```

在 `lib/state/playback_queue.dart` 的 `PlaybackQueueState` 加：
```dart
  String? get currentGroupDirPath {
    final s = series;
    if (s == null || currentIndex < 0) return null;
    var idx = currentIndex;
    for (final g in s.groups) {
      if (idx < g.episodes.length) return g.dirPath;
      idx -= g.episodes.length;
    }
    return null;
  }
```

- [ ] **Step 7: 全量 + analyze** — `flutter test && flutter analyze` 全绿。
- [ ] **Step 8: Commit** — `git commit -m "feat: persistent skip-config store, provider, current-group dirPath"`

---

### Task 4: 自动跳 watcher

**Files:** Create `lib/state/skip_watcher.dart`; Test `test/state/skip_watcher_test.dart`

**Interfaces:**
- Consumes: `positionProvider`/`durationProvider`/`playerEngineProvider`（T2、已有）、`playbackQueueProvider`（+currentGroupDirPath T3）、`skipConfigProvider`（T3）、`autoAdvanceProvider`（已有）
- Produces: `skipWatcherProvider` (Provider<SkipWatcher>)；需被 watch 才存活（T5 在 player_page watch）。

- [ ] **Step 1: 失败测试**

```dart
// test/state/skip_watcher_test.dart
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
```
> 注：`loadSeries` 会 `playAt(0)` 触发引擎 open/play 并把 position 置 0（fake.seek 不被调用；open 不 emit position）。watcher 通过 `currentEpisode.path` 做一次性 key。第二个测试里"关→开"切换后用更大的 position 触发；因 outro 一次性按集，故同集第二次 emit 仍是同集——实现需保证：未触发过(_outroDone=false 因第一次 autoAdvance 关时**也要置 _outroDone**？) — 见实现说明。

- [ ] **Step 2: 确认失败** — FAIL。

- [ ] **Step 3: 实现 watcher**

> 设计要点：outro 命中即置 `_outroDone=true`（无论是否真的 next），避免反复判断；但上面的测试需要"关闭时不跳、开启后再跳"。为兼容：**outro 命中时，若 autoAdvance 为假则不置 _outroDone（留待开启后再触发）**；为真则 next 并置 _outroDone。intro 命中即置 _introDone。

```dart
// lib/state/skip_watcher.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/playback_settings.dart';
import 'package:jump_player/state/skip_providers.dart';

class SkipWatcher {
  SkipWatcher(this._ref) {
    _sub = _ref.listen<AsyncValue<Duration>>(positionProvider, (_, next) {
      final pos = next.value;
      if (pos != null) _onPosition(pos);
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<Duration>> _sub;

  String? _episodePath;
  bool _introDone = false;
  bool _outroDone = false;

  void _onPosition(Duration pos) {
    final queue = _ref.read(playbackQueueProvider);
    final path = queue.currentEpisode?.path;
    if (path != _episodePath) {
      _episodePath = path;
      _introDone = false;
      _outroDone = false;
    }
    final dirPath = queue.currentGroupDirPath;
    if (dirPath == null) return;
    final cfg = _ref.read(skipConfigProvider.notifier).configFor(dirPath);
    final d = (_ref.read(durationProvider).value ?? Duration.zero).inSeconds;
    final p = pos.inSeconds;

    if (!_introDone &&
        cfg.introSeconds > 0 &&
        (d == 0 || cfg.introSeconds < d) &&
        p < cfg.introSeconds) {
      _introDone = true;
      _ref.read(playerEngineProvider).seek(Duration(seconds: cfg.introSeconds));
      return;
    }

    if (!_outroDone &&
        cfg.outroSeconds > 0 &&
        d > 0 &&
        p >= d - cfg.outroSeconds) {
      if (_ref.read(autoAdvanceProvider)) {
        _outroDone = true;
        _ref.read(playbackQueueProvider.notifier).next();
      }
    }
  }

  void dispose() => _sub.close();
}

final skipWatcherProvider = Provider<SkipWatcher>((ref) {
  final w = SkipWatcher(ref);
  ref.onDispose(w.dispose);
  return w;
});
```

- [ ] **Step 4: 跑测试确认通过 + 全量 + analyze** — `flutter test && flutter analyze` 全绿。
- [ ] **Step 5: Commit** — `git commit -m "feat: auto-skip watcher for intro/outro"`

---

### Task 5: 底部跳过设置条 + 接线

**Files:** Create `lib/ui/skip_settings_bar.dart`; Modify `lib/ui/player_page.dart`; Test `test/ui/skip_settings_bar_test.dart`

**Interfaces:**
- Consumes: `playbackQueueProvider`（currentGroupDirPath）、`skipConfigProvider`、`positionProvider`、`durationProvider`、`skipWatcherProvider`
- Produces: `class SkipSettingsBar extends ConsumerStatefulWidget`

- [ ] **Step 1: 失败测试**

```dart
// test/ui/skip_settings_bar_test.dart
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
```

- [ ] **Step 2: 确认失败** — FAIL。

- [ ] **Step 3: 实现 SkipSettingsBar**

```dart
// lib/ui/skip_settings_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/skip_providers.dart';

class SkipSettingsBar extends ConsumerStatefulWidget {
  const SkipSettingsBar({super.key});
  @override
  ConsumerState<SkipSettingsBar> createState() => _SkipSettingsBarState();
}

class _SkipSettingsBarState extends ConsumerState<SkipSettingsBar> {
  final _intro = TextEditingController();
  final _outro = TextEditingController();
  String? _dirPath;

  @override
  void dispose() {
    _intro.dispose();
    _outro.dispose();
    super.dispose();
  }

  void _syncFields(String dirPath) {
    if (_dirPath == dirPath) return;
    _dirPath = dirPath;
    final cfg = ref.read(skipConfigProvider.notifier).configFor(dirPath);
    _intro.text = cfg.introSeconds.toString();
    _outro.text = cfg.outroSeconds.toString();
  }

  int _posSeconds() =>
      (ref.read(positionProvider).value ?? Duration.zero).inSeconds;
  int _durSeconds() =>
      (ref.read(durationProvider).value ?? Duration.zero).inSeconds;

  @override
  Widget build(BuildContext context) {
    final dirPath = ref.watch(
        playbackQueueProvider.select((s) => s.currentGroupDirPath));
    if (dirPath == null) return const SizedBox.shrink();
    _syncFields(dirPath);
    final notifier = ref.read(skipConfigProvider.notifier);

    Widget field(String label, TextEditingController ctl, String markKey,
        VoidCallback onMark, ValueChanged<String> onSubmit) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          child: TextField(
            controller: ctl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
            onSubmitted: onSubmit,
          ),
        ),
        const Text('s', style: TextStyle(color: Colors.white70)),
        TextButton(
          key: Key(markKey),
          onPressed: onMark,
          child: const Text('标记'),
        ),
      ]);
    }

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        field('片头', _intro, 'mark-intro',
            () => notifier.setIntro(dirPath, _posSeconds()),
            (v) => notifier.setIntro(dirPath, int.tryParse(v) ?? 0)),
        const SizedBox(width: 16),
        field('片尾', _outro, 'mark-outro', () {
          final m = _durSeconds() - _posSeconds();
          notifier.setOutro(dirPath, m < 0 ? 0 : m);
        }, (v) => notifier.setOutro(dirPath, int.tryParse(v) ?? 0)),
      ]),
    );
  }
}
```
> 标记后让输入框反映新值：标记回调里 `setIntro/Outro` 后，可 `setState(() { _intro.text = ...; })`；最简做法是在 onMark 里直接更新对应 controller.text。实施者补：mark-intro 后 `_intro.text = _posSeconds().toString();`，mark-outro 后 `_outro.text = m.toString();`（在 setState 中）。

- [ ] **Step 4: 接线 player_page**

`lib/ui/player_page.dart`：`import` skip_settings_bar 与 skip_watcher；在 build 顶部 `ref.watch(skipWatcherProvider);`（启动自动跳）；在 `Column` 里 `ControlBar` 之后加 `const SkipSettingsBar()`。

- [ ] **Step 5: 跑全量 + analyze** — `flutter test && flutter analyze` 全绿。
- [ ] **Step 6: Commit** — `git commit -m "feat: bottom skip-settings bar (mark/manual) + wire auto-skip"`

---

## Self-Review
- 域模型/持久化 → T1/T3。durationStream → T2。自动跳（片头 seek、片尾受连播门控、一次性、切集重置）→ T4。标记+手填+底部常驻条 → T5。当前剧 dirPath → T3 getter。
- 占位符：T3 Step4 的 currentGroupDirPath 测试与 T4/T5 的异步时序以注释give指引；实施者按相邻测试的 ProviderContainer/await 模式补全真实断言（StreamProvider 值需 `await Future.delayed(Duration.zero)` 再读 `.value`）。其余均含完整代码。
- 类型一致：`SkipConfig(introSeconds,outroSeconds)`、`PreferencesSkipStore.load/save`、`skipConfigProvider`/`SkipConfigController.configFor/setIntro/setOutro/clear`、`PlayerEngine.durationStream`/`FakePlayerEngine.emitDuration/emitPosition/seekedTo`、`durationProvider`、`PlaybackQueueState.currentGroupDirPath`、`skipWatcherProvider`、`SkipSettingsBar` 跨任务一致。
