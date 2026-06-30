# 跳过片头/片尾（同剧集）— 设计文档

日期：2026-06-29
状态：已确认，待转实现计划

## 目标
按"同剧集"（同文件夹/组）配置片头、片尾，对该剧所有集自动生效：
- **片头**：每集开始自动 seek 跳过开头 N 秒。
- **片尾**：每集播到"末尾 M 秒"处自动跳下一集（跳过片尾）。
- 设置方式同时支持：看片时**标记当前位置**、以及**手填秒数**。
- 设置入口是底部一条**常驻"跳过设置条"**（非弹框）。

## 关键决策（已确认）
- 配置粒度：按剧目录 `group.dirPath`（稳定唯一键），对该剧所有集生效。
- 片头/片尾都按**距边缘秒数**存（片头=从头 N 秒；片尾=末尾 M 秒），自适应各集时长差异。
- 自动跳（非按钮提示）。
- 片尾"跳下一集"**仅在自动连播开启时**生效（与自动连播开关一致，避免冲突）。
- 设置 UI 放在**最下面的常驻条**：标记片头、标记片尾、两个可手填秒数框。
- 持久化（shared_preferences）。

## 架构总览

```
domain/playback/
  skip_config.dart            ← 新增：SkipConfig(introSeconds,outroSeconds) + 纯数据/JSON
  player_engine.dart          ← 加 Stream<Duration> durationStream（Fake 同步加）

infra/playback/
  media_kit_player_engine.dart← durationStream = _player.stream.duration
infra/config/
  preferences_skip_store.dart ← 新增：持久化 Map<dirPath,SkipConfig>(JSON)

state/
  playback_providers.dart     ← 加 durationProvider (StreamProvider<Duration>)
  skip_providers.dart         ← 新增：skipConfigProvider(StateNotifier<Map<String,SkipConfig>>) + 当前剧 dirPath 派生 + 自动跳 watcher
  playback_queue.dart         ← 复用 next()/playAt()/currentEpisode；加"当前组 dirPath"辅助
  playback_settings.dart      ← 复用 autoAdvanceProvider（片尾跳下一集的门控）

ui/
  skip_settings_bar.dart      ← 新增：底部常驻条（标记片头/片尾 + 手填秒数）
  player_page.dart            ← 在 ControlBar 下方加 SkipSettingsBar
```

## 数据模型 & 持久化

`SkipConfig`（纯数据）：
```
final int introSeconds;   // 从头跳过的秒数，0 = 不跳片头
final int outroSeconds;   // 末尾跳过的秒数，0 = 不跳片尾
toJson()/fromJson()，copyWith()
```

`SkipConfigStore`（infra）：用 shared_preferences 键 `skip_config_v1` 存一个 JSON 对象 `{ "<dirPath>": {"intro":N,"outro":M}, ... }`。load 返回 `Map<String,SkipConfig>`（无值=空 map）；save 全量写回。解析失败回退空 map。

## 引擎补时长
`PlayerEngine` 增 `Stream<Duration> get durationStream;`：
- `MediaKitPlayerEngine` → `_player.stream.duration`。
- `FakePlayerEngine` → 新增 `_duration` broadcast controller + `emitDuration(Duration)`，dispose 关闭。
- `playback_providers.dart` 增 `durationProvider = StreamProvider<Duration>((ref)=>engine.durationStream)`。

## 状态层

`skipConfigProvider`（StateNotifier<Map<String,SkipConfig>>，构造时从 store 异步载入）：
- `SkipConfig configFor(String dirPath)`（无则返回 `SkipConfig(0,0)`）。
- `Future<void> setIntro(String dirPath,int seconds)` / `setOutro(...)` / `clear(String dirPath)`：更新 state 并持久化。

**当前剧 dirPath 派生**：从 `playbackQueueProvider` 的 `series.groups` 与 `currentIndex` 算出当前播放集所属组的 `dirPath`（无则 null）。在 `PlaybackQueueState` 加 getter `String? get currentGroupDirPath`（遍历组累加下标定位）。

**自动跳 watcher**（`skipWatcherProvider` 或一个在 provider 内 `ref.listen` 的控制器）：
监听 `positionProvider`；读取 `durationProvider`、当前 `currentGroupDirPath` 的 `SkipConfig`、`autoAdvanceProvider`、引擎与队列。
- 维护 per-episode 一次性标记，key 用当前 `currentEpisode.path`（切集即变 → 自动重置）：`_introDone`、`_outroDone`。
- **片头**：`introSeconds>0 && introSeconds<duration && 0<=pos<introSeconds && !_introDone` → `engine.seek(introSeconds)`，置 `_introDone`。
- **片尾**：`outroSeconds>0 && duration>0 && pos >= duration-outroSeconds && !_outroDone` → 置 `_outroDone`；若 `autoAdvanceProvider` 为真 → `queue.next()`。
- 时长/位置为 0 或未知时不动；片头跳点 ≥ 片尾起点时只执行片头（防越界）。

## UI：底部跳过设置条
`SkipSettingsBar`（放在 `player_page.dart` 的 `ControlBar` 下方，深色背景统一主题）：
- 仅当有当前播放集（`currentGroupDirPath != null`）时显示；否则隐藏。
- 一行：`片头 [____]s [标记]    片尾 [____]s [标记]`
  - 两个紧凑数字输入框，预填当前剧的 intro/outro 秒数；提交即 `setIntro/setOutro(dirPath, 值)` 持久化。
  - 「标记」片头：`setIntro(dirPath, 当前位置.inSeconds)`。
  - 「标记」片尾：`setOutro(dirPath, (时长-当前位置).inSeconds.clamp(0,...))`。
  - 当前位置取 `positionProvider`，时长取 `durationProvider`。
- 视觉：白字、深底，紧凑，不喧宾夺主。

## 错误处理 / 边界
- 时长未知（0）：片尾不触发；标记片尾按钮在时长未知时禁用。
- intro ≥ duration：跳过片头逻辑跳过（不 seek 到越界）。
- 末集片尾触发且自动连播开：`next()` 无下一集时为 no-op（播完片尾即结束）。
- 用户手动拖动：一次性标记防止反复 seek；切集重置。
- skip_config JSON 解析失败 → 空 map，不崩。

## 测试策略
- domain：`skip_config_test`（序列化/默认/copyWith）。
- infra：`preferences_skip_store_test`（往返、空、坏 JSON 回退）。
- state：`skip_providers_test`（configFor/setIntro/setOutro 持久化；当前组 dirPath 派生）；自动跳 watcher（注入 Fake 引擎发 position/duration：到点 seek 片头一次、到点片尾在连播开时 next、连播关时不 next、切集重置）。
- engine：FakePlayerEngine.durationStream/emitDuration。
- ui：`skip_settings_bar_test`（无播放隐藏；标记片头/片尾按当前位置/时长写入 provider；手填提交持久化）。

## 依赖
- 复用 `shared_preferences`（已在）。无新增包。

## 影响面
- `PlayerEngine` 接口新增方法 → 影响所有实现/伪实现与相关测试（FakePlayerEngine）。
- `PlaybackQueueState` 新增 getter（非破坏）。
- `player_page.dart` 布局新增一行（ControlBar 下）。
