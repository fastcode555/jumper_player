# P2 媒体库 + 扫描 + 侧边栏连播 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户选一个根文件夹 → 递归扫描出视频文件 → 按集号自然排序成剧集列表 → 在播放页侧边栏点击跳集、上一集/下一集、播完自动连播。

**Architecture:** 纯 Dart 领域层承担全部可测逻辑（`EpisodeSorter` 集号解析+自然排序、`LibraryScanner` 递归扫描）。播放队列状态由 Riverpod `PlaybackQueueController`（StateNotifier）管理，复用 P1 的 `PlayerEngine` 抽象驱动实际播放，并订阅新增的 `completedStream` 实现自动连播。UI 新增「打开文件夹」动作与可折叠剧集侧边栏。**本期不做持久化（Drift 推到 P3）**，剧集库为内存态，每次添加文件夹即时扫描。

**Tech Stack:** Flutter, media_kit, hooks_riverpod, file_picker (含 `getDirectoryPath`), dart:io（扫描，仅桌面/测试），flutter_test。

## Global Constraints

- 单一代码库 write once；播放引擎仍为 media_kit（libmpv），禁用 video_player。
- 领域层 `lib/domain/` 为纯 Dart：`episode_sorter.dart` 仅用 `dart:core`（不 import flutter）；`library_scanner.dart` 可用 `dart:io`（扫描需要），仍须在 `flutter test` 下无设备运行（测试用临时目录）。
- 状态管理用 Riverpod；剧集库本期为内存态，**不引入 Drift**（持久化留到 P3）。
- 集号解析按固定优先级正则，命中即停；解析全失败退回路径自然排序。自然排序须数值化（`9集` 排在 `123集` 前）。
- 保留 P1 的「打开文件」单文件播放，新增「打开文件夹」。
- TDD；测试验证真实行为；每个任务以独立可测交付物结束；频繁提交。
- 移动端（Android SAF / iOS）的目录访问差异本期不处理，P2 仅保证桌面三端；移动端目录选择降级留待后续。

---

### Task 1: Episode 与 Series 领域模型

**Files:**
- Create: `lib/domain/library/library_models.dart`
- Test: `test/domain/library/library_models_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class Episode { final String path; final String fileName; final int? season; final int? episodeNumber; const Episode(...); }` 含 `==`/`hashCode`（按 path）。
  - `class Series { final String name; final String rootPath; final List<Episode> episodes; const Series(...); }`。

- [ ] **Step 1: 写失败测试**

`test/domain/library/library_models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';

void main() {
  test('Episode equality is based on path', () {
    const a = Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1);
    const b = Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1);
    const c = Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2);
    expect(a, b);
    expect(a == c, isFalse);
  });

  test('Series holds ordered episodes', () {
    const eps = [
      Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
      Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
    ];
    const s = Series(name: 'X', rootPath: '/x', episodes: eps);
    expect(s.name, 'X');
    expect(s.episodes.length, 2);
    expect(s.episodes.first.episodeNumber, 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/library/library_models_test.dart`
Expected: FAIL（`library_models.dart` 不存在）

- [ ] **Step 3: 写实现**

`lib/domain/library/library_models.dart`:
```dart
class Episode {
  const Episode({
    required this.path,
    required this.fileName,
    this.season,
    this.episodeNumber,
  });

  final String path;
  final String fileName;
  final int? season;
  final int? episodeNumber;

  @override
  bool operator ==(Object other) =>
      other is Episode && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class Series {
  const Series({
    required this.name,
    required this.rootPath,
    required this.episodes,
  });

  final String name;
  final String rootPath;
  final List<Episode> episodes;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/domain/library/library_models_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/domain/library/library_models.dart test/domain/library/library_models_test.dart
git commit -m "feat: add Episode and Series library models"
```

---

### Task 2: EpisodeSorter — 集号解析 + 自然排序

**Files:**
- Create: `lib/domain/library/episode_sorter.dart`
- Test: `test/domain/library/episode_sorter_test.dart`

**Interfaces:**
- Consumes: `Episode`（Task 1）
- Produces:
  - `class ParsedEpisode { final int? season; final int episode; const ParsedEpisode(this.season, this.episode); }`
  - `class EpisodeSorter`:
    - `static ParsedEpisode? parse(String fileName)` — 优先级正则提取。
    - `static int compareNatural(String a, String b)` — 数值化自然排序。
    - `static List<Episode> sort(List<Episode> items)` — 返回新排序列表。

- [ ] **Step 1: 写失败测试**

`test/domain/library/episode_sorter_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/episode_sorter.dart';

void main() {
  group('parse', () {
    test('SxxExx', () {
      final p = EpisodeSorter.parse('权游.S01E02.mkv')!;
      expect(p.season, 1);
      expect(p.episode, 2);
    });
    test('中文 第N集', () {
      expect(EpisodeSorter.parse('吞噬星空第123集.mp4')!.episode, 123);
    });
    test('中文 N集 无第', () {
      expect(EpisodeSorter.parse('吞噬星空123集.mp4')!.episode, 123);
    });
    test('分辨率干扰下仍取集号', () {
      expect(EpisodeSorter.parse('吞噬星空4K.123集.mp4')!.episode, 123);
    });
    test('EP 前缀', () {
      expect(EpisodeSorter.parse('EP123.mp4')!.episode, 123);
    });
    test('E05 而非年份/分辨率', () {
      final p = EpisodeSorter.parse('某剧.2024.1080p.E05.mkv')!;
      expect(p.episode, 5);
    });
    test('末尾独立数字兜底', () {
      expect(EpisodeSorter.parse('吞噬星空123.mp4')!.episode, 123);
    });
    test('无数字返回 null', () {
      expect(EpisodeSorter.parse('片头曲.mkv'), isNull);
    });
  });

  group('compareNatural', () {
    test('9 排在 123 前', () {
      expect(EpisodeSorter.compareNatural('ep9.mkv', 'ep123.mkv'), lessThan(0));
    });
  });

  group('sort', () {
    test('按集号数值排序而非字典序', () {
      const items = [
        Episode(path: '/a/第10集.mkv', fileName: '第10集.mkv', episodeNumber: 10),
        Episode(path: '/a/第2集.mkv', fileName: '第2集.mkv', episodeNumber: 2),
        Episode(path: '/a/第1集.mkv', fileName: '第1集.mkv', episodeNumber: 1),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.episodeNumber), [1, 2, 10]);
    });

    test('有集号的排在无集号之前；无集号按自然名', () {
      const items = [
        Episode(path: '/a/花絮.mkv', fileName: '花絮.mkv'),
        Episode(path: '/a/E2.mkv', fileName: 'E2.mkv', episodeNumber: 2),
        Episode(path: '/a/E1.mkv', fileName: 'E1.mkv', episodeNumber: 1),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.fileName), ['E1.mkv', 'E2.mkv', '花絮.mkv']);
    });

    test('按季再按集', () {
      const items = [
        Episode(path: '/a/S2E1.mkv', fileName: 'S2E1.mkv', season: 2, episodeNumber: 1),
        Episode(path: '/a/S1E2.mkv', fileName: 'S1E2.mkv', season: 1, episodeNumber: 2),
      ];
      final sorted = EpisodeSorter.sort(items);
      expect(sorted.map((e) => e.fileName), ['S1E2.mkv', 'S2E1.mkv']);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/library/episode_sorter_test.dart`
Expected: FAIL（`episode_sorter.dart` 不存在）

- [ ] **Step 3: 写实现**

`lib/domain/library/episode_sorter.dart`:
```dart
import 'package:jump_player/domain/library/library_models.dart';

class ParsedEpisode {
  const ParsedEpisode(this.season, this.episode);
  final int? season;
  final int episode;
}

class EpisodeSorter {
  // 按优先级排列，命中即停。
  static final RegExp _sxxExx =
      RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');
  static final RegExp _cnWithPrefix =
      RegExp(r'第\s*(\d{1,4})\s*[集話话期]');
  static final RegExp _cnNoPrefix =
      RegExp(r'(\d{1,4})\s*[集話话期]');
  static final RegExp _epPrefix =
      RegExp(r'\b[Ee][Pp]?(\d{1,4})\b');
  static final RegExp _anyNumber = RegExp(r'\d{1,4}');

  static ParsedEpisode? parse(String fileName) {
    final m1 = _sxxExx.firstMatch(fileName);
    if (m1 != null) {
      return ParsedEpisode(int.parse(m1.group(1)!), int.parse(m1.group(2)!));
    }
    final m2 = _cnWithPrefix.firstMatch(fileName);
    if (m2 != null) {
      return ParsedEpisode(null, int.parse(m2.group(1)!));
    }
    final m3 = _cnNoPrefix.firstMatch(fileName);
    if (m3 != null) {
      return ParsedEpisode(null, int.parse(m3.group(1)!));
    }
    final m4 = _epPrefix.firstMatch(fileName);
    if (m4 != null) {
      return ParsedEpisode(null, int.parse(m4.group(1)!));
    }
    final all = _anyNumber.allMatches(fileName).toList();
    if (all.isNotEmpty) {
      return ParsedEpisode(null, int.parse(all.last.group(0)!));
    }
    return null;
  }

  /// 数值化自然排序：把字符串拆成数字块/非数字块逐块比较。
  static int compareNatural(String a, String b) {
    final sa = a.toLowerCase();
    final sb = b.toLowerCase();
    int i = 0, j = 0;
    while (i < sa.length && j < sb.length) {
      final ca = sa.codeUnitAt(i);
      final cb = sb.codeUnitAt(j);
      final da = ca >= 0x30 && ca <= 0x39;
      final db = cb >= 0x30 && cb <= 0x39;
      if (da && db) {
        int si = i, sj = j;
        while (i < sa.length && _isDigit(sa.codeUnitAt(i))) {
          i++;
        }
        while (j < sb.length && _isDigit(sb.codeUnitAt(j))) {
          j++;
        }
        final na = int.parse(sa.substring(si, i));
        final nb = int.parse(sb.substring(sj, j));
        if (na != nb) return na.compareTo(nb);
      } else {
        if (ca != cb) return ca.compareTo(cb);
        i++;
        j++;
      }
    }
    return (sa.length - i).compareTo(sb.length - j);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static List<Episode> sort(List<Episode> items) {
    final copy = [...items];
    copy.sort((a, b) {
      final ae = a.episodeNumber;
      final be = b.episodeNumber;
      if (ae != null && be != null) {
        final sa = a.season ?? 0;
        final sb = b.season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        return ae.compareTo(be);
      }
      if (ae != null && be == null) return -1;
      if (ae == null && be != null) return 1;
      return compareNatural(a.fileName, b.fileName);
    });
    return copy;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/domain/library/episode_sorter_test.dart`
Expected: PASS（全部用例）

- [ ] **Step 5: 提交**

```bash
git add lib/domain/library/episode_sorter.dart test/domain/library/episode_sorter_test.dart
git commit -m "feat: add EpisodeSorter with priority parsing and natural sort"
```

---

### Task 3: LibraryScanner — 递归扫描文件夹

**Files:**
- Create: `lib/domain/library/library_scanner.dart`
- Test: `test/domain/library/library_scanner_test.dart`

**Interfaces:**
- Consumes: `Episode`, `Series`（Task 1）；`EpisodeSorter`（Task 2）
- Produces:
  - `class LibraryScanner`:
    - `static const Set<String> videoExtensions`
    - `Future<Series> scan(String rootPath)` — 递归收集视频文件 → 每个文件经 `EpisodeSorter.parse` 赋季/集 → `EpisodeSorter.sort` 排序 → 返回 `Series`（name 取根目录名）。

- [ ] **Step 1: 写失败测试**

`test/domain/library/library_scanner_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_scanner.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_test_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('flat layout: sorts by episode, skips non-video', () async {
    File('${tmp.path}/吞噬星空第2集.mp4').writeAsStringSync('x');
    File('${tmp.path}/吞噬星空第10集.mp4').writeAsStringSync('x');
    File('${tmp.path}/吞噬星空第1集.mp4').writeAsStringSync('x');
    File('${tmp.path}/字幕.ass').writeAsStringSync('x');

    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.map((e) => e.episodeNumber), [1, 2, 10]);
    expect(
      series.episodes.every((e) => e.fileName.endsWith('.mp4')),
      isTrue,
    );
  });

  test('nested layout (one episode per subfolder) flattens to ordered list',
      () async {
    Directory('${tmp.path}/E01').createSync();
    Directory('${tmp.path}/E02').createSync();
    File('${tmp.path}/E01/show.S01E01.mkv').writeAsStringSync('x');
    File('${tmp.path}/E02/show.S01E02.mkv').writeAsStringSync('x');

    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.length, 2);
    expect(series.episodes.map((e) => e.episodeNumber), [1, 2]);
  });

  test('series name is the root folder name', () async {
    final sub = Directory('${tmp.path}/权力的游戏')..createSync();
    File('${sub.path}/S01E01.mkv').writeAsStringSync('x');
    final series = await LibraryScanner().scan(sub.path);
    expect(series.name, '权力的游戏');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/library/library_scanner_test.dart`
Expected: FAIL（`library_scanner.dart` 不存在）

- [ ] **Step 3: 写实现**

`lib/domain/library/library_scanner.dart`:
```dart
import 'dart:io';

import 'package:jump_player/domain/library/episode_sorter.dart';
import 'package:jump_player/domain/library/library_models.dart';

class LibraryScanner {
  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.flv', '.ts',
    '.webm', '.m4v', '.wmv', '.rmvb', '.rm', '.mpg', '.mpeg',
  };

  Future<Series> scan(String rootPath) async {
    final root = Directory(rootPath);
    final episodes = <Episode>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      final ext = _extension(name).toLowerCase();
      if (!videoExtensions.contains(ext)) continue;
      final parsed = EpisodeSorter.parse(name);
      episodes.add(Episode(
        path: entity.path,
        fileName: name,
        season: parsed?.season,
        episodeNumber: parsed?.episode,
      ));
    }

    return Series(
      name: _baseName(rootPath),
      rootPath: rootPath,
      episodes: EpisodeSorter.sort(episodes),
    );
  }

  static String _baseName(String path) {
    final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _extension(String name) {
    final idx = name.lastIndexOf('.');
    return idx >= 0 ? name.substring(idx) : '';
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/domain/library/library_scanner_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/domain/library/library_scanner.dart test/domain/library/library_scanner_test.dart
git commit -m "feat: add LibraryScanner for recursive folder scan into a Series"
```

---

### Task 4: PlayerEngine 增加 completedStream（自动连播所需）

**Files:**
- Modify: `lib/domain/playback/player_engine.dart`
- Modify: `lib/infra/playback/media_kit_player_engine.dart`
- Test: `test/domain/playback/player_engine_test.dart`（补一条 completed 测试）

**Interfaces:**
- Consumes: 现有 `PlayerEngine`、`FakePlayerEngine`、`MediaKitPlayerEngine`
- Produces:
  - `PlayerEngine` 新增 `Stream<bool> get completedStream`。
  - `FakePlayerEngine` 新增 `completedStream` + 测试辅助 `void emitCompleted()`（推送 `true`）。
  - `MediaKitPlayerEngine.completedStream => _player.stream.completed`。

- [ ] **Step 1: 写失败测试（追加到现有文件）**

在 `test/domain/playback/player_engine_test.dart` 的 `group('FakePlayerEngine', ...)` 内追加：
```dart
    test('emitCompleted pushes onto completedStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <bool>[];
      final sub = engine.completedStream.listen(emitted.add);
      engine.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [true]);
      await sub.cancel();
    });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain/playback/player_engine_test.dart`
Expected: FAIL（`completedStream` / `emitCompleted` 未定义）

- [ ] **Step 3: 修改 PlayerEngine 接口与 Fake**

在 `lib/domain/playback/player_engine.dart` 的 `abstract class PlayerEngine` 中，于 `playingStream` getter 后新增：
```dart
  Stream<bool> get completedStream;
```
在 `FakePlayerEngine` 中：新增字段与实现（放在 `_playing` 字段旁）：
```dart
  final _completed = StreamController<bool>.broadcast();
```
新增 getter（放在 `playingStream` getter 后）：
```dart
  @override
  Stream<bool> get completedStream => _completed.stream;

  void emitCompleted() => _completed.add(true);
```
并在 `dispose()` 中关闭它：
```dart
  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
    await _completed.close();
  }
```

- [ ] **Step 4: 修改 MediaKitPlayerEngine**

在 `lib/infra/playback/media_kit_player_engine.dart` 的 `playingStream` getter 后新增：
```dart
  @override
  Stream<bool> get completedStream => _player.stream.completed;
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/domain/playback/player_engine_test.dart`
Expected: PASS（4/4）

- [ ] **Step 6: analyze 确认无误**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 7: 提交**

```bash
git add lib/domain/playback/player_engine.dart lib/infra/playback/media_kit_player_engine.dart test/domain/playback/player_engine_test.dart
git commit -m "feat: add completedStream to PlayerEngine for auto-advance"
```

---

### Task 5: PlaybackQueueController — 队列状态与上/下一集/自动连播

**Files:**
- Create: `lib/state/playback_queue.dart`
- Test: `test/state/playback_queue_test.dart`

**Interfaces:**
- Consumes: `playerEngineProvider`（P1）、`PlayerEngine`/`FakePlayerEngine`、`Episode`/`Series`
- Produces:
  - `class PlaybackQueueState { final Series? series; final int currentIndex; const PlaybackQueueState({this.series, this.currentIndex = -1}); }` 含 `episodes` getter、`hasNext`/`hasPrevious`/`currentEpisode`。
  - `class PlaybackQueueController extends StateNotifier<PlaybackQueueState>`：
    - `Future<void> loadSeries(Series series, {int startAt = 0})`
    - `Future<void> playAt(int index)`
    - `Future<void> next()` / `Future<void> previous()`
    - 构造时订阅 `engine.completedStream`，`autoNext` 为真且 `hasNext` 时自动 `next()`；`autoNext` 默认 `true`。
  - `final playbackQueueProvider = StateNotifierProvider<PlaybackQueueController, PlaybackQueueState>(...)`。

- [ ] **Step 1: 写失败测试**

`test/state/playback_queue_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';

Series _series() => const Series(name: 'X', rootPath: '/x', episodes: [
      Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
      Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
      Episode(path: '/x/e3.mkv', fileName: 'e3.mkv', episodeNumber: 3),
    ]);

void main() {
  late FakePlayerEngine fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakePlayerEngine();
    container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
  });
  tearDown(() => container.dispose());

  test('loadSeries plays the start episode', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    expect(fake.openedPath, '/x/e1.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 0);
  });

  test('next and previous walk the list', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    await c.next();
    expect(fake.openedPath, '/x/e2.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 1);
    await c.previous();
    expect(fake.openedPath, '/x/e1.mkv');
  });

  test('next at last episode is a no-op', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series(), startAt: 2);
    await c.next();
    expect(container.read(playbackQueueProvider).currentIndex, 2);
  });

  test('auto-advances on completion when not last', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    fake.emitCompleted();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(playbackQueueProvider).currentIndex, 1);
    expect(fake.openedPath, '/x/e2.mkv');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/state/playback_queue_test.dart`
Expected: FAIL（`playback_queue.dart` 不存在）

- [ ] **Step 3: 写实现**

`lib/state/playback_queue.dart`:
```dart
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

class PlaybackQueueState {
  const PlaybackQueueState({this.series, this.currentIndex = -1});

  final Series? series;
  final int currentIndex;

  List<Episode> get episodes => series?.episodes ?? const [];
  Episode? get currentEpisode =>
      (currentIndex >= 0 && currentIndex < episodes.length)
          ? episodes[currentIndex]
          : null;
  bool get hasNext => currentIndex >= 0 && currentIndex < episodes.length - 1;
  bool get hasPrevious => currentIndex > 0;
}

class PlaybackQueueController extends StateNotifier<PlaybackQueueState> {
  PlaybackQueueController(this._engine) : super(const PlaybackQueueState()) {
    _completedSub = _engine.completedStream.listen((_) {
      if (autoNext && state.hasNext) {
        next();
      }
    });
  }

  final PlayerEngine _engine;
  late final StreamSubscription<bool> _completedSub;
  bool autoNext = true;

  Future<void> loadSeries(Series series, {int startAt = 0}) async {
    state = PlaybackQueueState(series: series, currentIndex: -1);
    if (series.episodes.isEmpty) return;
    final idx = startAt.clamp(0, series.episodes.length - 1);
    await playAt(idx);
  }

  Future<void> playAt(int index) async {
    final eps = state.episodes;
    if (index < 0 || index >= eps.length) return;
    state = PlaybackQueueState(series: state.series, currentIndex: index);
    await _engine.open(eps[index].path);
    await _engine.play();
  }

  Future<void> next() async {
    if (state.hasNext) await playAt(state.currentIndex + 1);
  }

  Future<void> previous() async {
    if (state.hasPrevious) await playAt(state.currentIndex - 1);
  }

  @override
  void dispose() {
    _completedSub.cancel();
    super.dispose();
  }
}

final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueController, PlaybackQueueState>((ref) {
  final engine = ref.watch(playerEngineProvider);
  return PlaybackQueueController(engine);
});
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/state/playback_queue_test.dart`
Expected: PASS（4/4）

- [ ] **Step 5: 提交**

```bash
git add lib/state/playback_queue.dart test/state/playback_queue_test.dart
git commit -m "feat: add PlaybackQueueController with prev/next and auto-advance"
```

---

### Task 6: 「打开文件夹」动作 — 扫描并载入剧集

**Files:**
- Create: `lib/state/library_actions.dart`
- Modify: `lib/ui/player_page.dart`（新增「打开文件夹」按钮）
- Test: `test/state/library_actions_test.dart`

**Interfaces:**
- Consumes: `LibraryScanner`、`playbackQueueProvider`（Task 5）、`file_picker`
- Produces:
  - `class LibraryActions { LibraryActions(this._scanner, this._queue); Future<void> openFolder(String path); }` — 扫描路径 → `loadSeries`。把扫描与 UI 解耦以便单测（UI 只负责弹目录选择器拿到 path）。
  - `final libraryActionsProvider = Provider<LibraryActions>(...)`。
  - PlayerPage 新增「打开文件夹」`ElevatedButton`：`FilePicker.platform.getDirectoryPath()` → 非空则 `libraryActions.openFolder(path)`，含 try/catch + SnackBar（与 P1「打开文件」一致的错误处理）。

- [ ] **Step 1: 写失败测试**

`test/state/library_actions_test.dart`:
```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/library_actions.dart';

void main() {
  test('openFolder scans and loads first episode into the queue', () async {
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
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/state/library_actions_test.dart`
Expected: FAIL（`library_actions.dart` 不存在）

- [ ] **Step 3: 写 LibraryActions 实现**

`lib/state/library_actions.dart`:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_scanner.dart';
import 'package:jump_player/state/playback_queue.dart';

class LibraryActions {
  LibraryActions(this._scanner, this._queue);

  final LibraryScanner _scanner;
  final PlaybackQueueController _queue;

  Future<void> openFolder(String path) async {
    final series = await _scanner.scan(path);
    await _queue.loadSeries(series);
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(
    LibraryScanner(),
    ref.watch(playbackQueueProvider.notifier),
  );
});
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/state/library_actions_test.dart`
Expected: PASS

- [ ] **Step 5: 在 PlayerPage 增加「打开文件夹」按钮**

在 `lib/ui/player_page.dart` 的控制层 `Column` 中，于「打开文件」`ElevatedButton` 之后插入：
```dart
            ElevatedButton(
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
              child: const Text('打开文件夹'),
            ),
```
并在文件顶部确保已 import `package:jump_player/state/library_actions.dart`。

- [ ] **Step 6: 运行全套测试 + analyze**

Run: `flutter test && flutter analyze`
Expected: 全 PASS；analyze 无 error。

- [ ] **Step 7: 提交**

```bash
git add lib/state/library_actions.dart lib/ui/player_page.dart test/state/library_actions_test.dart
git commit -m "feat: add open-folder action that scans and loads a series"
```

---

### Task 7: 剧集侧边栏 UI

**Files:**
- Create: `lib/state/ui_providers.dart`
- Create: `lib/ui/episode_sidebar.dart`
- Modify: `lib/ui/player_page.dart`（集成侧边栏 + 折叠开关 + 上/下一集按钮）
- Test: `test/ui/episode_sidebar_test.dart`

**Interfaces:**
- Consumes: `playbackQueueProvider`（Task 5）
- Produces:
  - `final sidebarVisibleProvider = StateProvider<bool>((ref) => true);`（`lib/state/ui_providers.dart`）
  - `class EpisodeSidebar extends ConsumerWidget` — 列出 `playbackQueueProvider.episodes`，高亮 `currentIndex`，点击某项 `playbackQueueProvider.notifier.playAt(i)`；顶部「上一集 / 下一集」按钮。
  - PlayerPage：在视频层之上叠加可折叠的 `EpisodeSidebar`（右侧），并加一个列表图标按钮切换 `sidebarVisibleProvider`。

- [ ] **Step 1: 写失败 widget 测试**

`test/ui/episode_sidebar_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/ui/episode_sidebar.dart';

void main() {
  testWidgets('lists episodes and highlights current; tap jumps', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(playbackQueueProvider.notifier).loadSeries(
          const Series(name: 'X', rootPath: '/x', episodes: [
            Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
            Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
          ]),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EpisodeSidebar())),
      ),
    );
    await tester.pump();

    expect(find.text('e1.mkv'), findsOneWidget);
    expect(find.text('e2.mkv'), findsOneWidget);

    await tester.tap(find.text('e2.mkv'));
    await tester.pump();
    expect(fake.openedPath, '/x/e2.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 1);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/episode_sidebar_test.dart`
Expected: FAIL（`episode_sidebar.dart` 不存在）

- [ ] **Step 3: 写 ui_providers 与 EpisodeSidebar**

`lib/state/ui_providers.dart`:
```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

final sidebarVisibleProvider = StateProvider<bool>((ref) => true);
```

`lib/ui/episode_sidebar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_queue.dart';

class EpisodeSidebar extends ConsumerWidget {
  const EpisodeSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackQueueProvider);
    final controller = ref.read(playbackQueueProvider.notifier);

    return Container(
      width: 280,
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.series?.name ?? '未载入剧集',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: state.hasPrevious ? controller.previous : null,
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next),
                  onPressed: state.hasNext ? controller.next : null,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: state.episodes.length,
              itemBuilder: (context, i) {
                final ep = state.episodes[i];
                final selected = i == state.currentIndex;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: Colors.white24,
                  title: Text(
                    ep.fileName,
                    style: TextStyle(
                      color: selected ? Colors.amber : Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => controller.playAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/episode_sidebar_test.dart`
Expected: PASS

- [ ] **Step 5: 在 PlayerPage 集成侧边栏 + 折叠开关**

在 `lib/ui/player_page.dart`：顶部 import `package:jump_player/state/ui_providers.dart` 与 `package:jump_player/ui/episode_sidebar.dart`。把最外层视频 `Stack` 改造成「视频 + 控制层 + 右侧侧边栏 + 折叠按钮」：将现有 `Stack` 的 children 末尾追加：
```dart
        // 右侧可折叠剧集侧边栏
        if (ref.watch(sidebarVisibleProvider))
          const Align(
            alignment: Alignment.centerRight,
            child: EpisodeSidebar(),
          ),
        // 折叠/展开开关（左上角）
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            color: Colors.white,
            icon: const Icon(Icons.playlist_play),
            onPressed: () => ref.read(sidebarVisibleProvider.notifier).state =
                !ref.read(sidebarVisibleProvider),
          ),
        ),
```

- [ ] **Step 6: 运行全套测试 + analyze**

Run: `flutter test && flutter analyze`
Expected: 全 PASS；analyze 无 error。

- [ ] **Step 7: 提交**

```bash
git add lib/state/ui_providers.dart lib/ui/episode_sidebar.dart lib/ui/player_page.dart test/ui/episode_sidebar_test.dart
git commit -m "feat: add collapsible episode sidebar with jump and prev/next"
```

---

### Task 8: 集成冒烟 + 文档

**Files:**
- Modify: `docs/RUNNING.md`（新增 P2 手动冒烟清单）

**Interfaces:**
- Consumes: 全部
- Produces: P2 手动验证步骤。

- [ ] **Step 1: 全量测试 + analyze**

Run: `flutter test && flutter analyze`
Expected: 全 PASS；analyze 无 error。

- [ ] **Step 2: 追加 P2 手动冒烟清单到 docs/RUNNING.md**

在 `docs/RUNNING.md` 末尾追加一节「## Manual Smoke Checklist (P2)」，内容包括：
1. 启动 app（`flutter run -d macos`）。
2. 点「打开文件夹」，选一个含多集视频的文件夹（嵌套或扁平均可）。
3. 右侧侧边栏应列出该文件夹下所有视频，按集号顺序排列，当前集高亮。
4. 点侧边栏某一集 → 跳转播放该集。
5. 点「上一集/下一集」→ 正确切换。
6. 一集播完 → 自动播放下一集。
7. 点左上角列表图标 → 侧边栏可折叠/展开。
说明：此清单需桌面 GUI 会话，人工执行。

- [ ] **Step 3: 提交**

```bash
git add docs/RUNNING.md
git commit -m "docs: add P2 media-library manual smoke checklist"
```

---

## Self-Review

**1. Spec coverage（P2 范围）:** 覆盖设计文档 §4（媒体库与扫描：根文件夹=剧集组、递归拉平、集号优先级解析、自然排序）+ §5（上一集/下一集、自动连播）+ §8 侧边栏剧集列表（本期 UI 决策）。持久化（§9 Drift）按设计与用户确认明确推迟到 P3。手动拆分/合并（D 修正）随持久化推迟。无 P2 范围内遗漏。

**2. Placeholder scan:** 无 TBD/TODO；每个代码步骤给出完整代码与确切命令。Task 4/6/7 的"修改现有文件"步骤给出了具体插入位置与完整代码片段。

**3. Type consistency:** `Episode`(path/fileName/season/episodeNumber)、`Series`(name/rootPath/episodes) 在 Task 1 定义，Task 2/3/5/6/7 一致引用。`EpisodeSorter.parse/compareNatural/sort`、`LibraryScanner.scan`、`PlaybackQueueController`(loadSeries/playAt/next/previous)、`PlaybackQueueState`(series/currentIndex/episodes/currentEpisode/hasNext/hasPrevious)、`playbackQueueProvider`、`libraryActionsProvider`、`sidebarVisibleProvider`、`completedStream`/`emitCompleted` 跨任务命名统一。Task 4 在 P1 的 `PlayerEngine` 上新增 `completedStream`，为附加变更不破坏既有签名。
