# 播放列表分组 + 文件名清洗映射 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把"剧集列表"按钮并入底部控制栏；在加载时为每个文件生成非破坏性的干净显示名（可配置、持久化）；播放列表按识别出的剧名分组、跨组自动续播。

**Architecture:** domain 层新增纯函数 `NameCleaner`（原始文件名 + 父目录名 + 配置 → 干净显示名 / 剧名 / 集号）与配置模型 `NameCleanConfig`；infra 层用 `shared_preferences` 持久化配置；`LibraryScanner` 改为产出按剧名分组的 `Series{groups}`；`PlaybackQueue` 在扁平全局顺序上运行（`Series.episodes` getter 展开 groups），侧边栏负责分组展示与全局索引换算。

**Tech Stack:** Flutter 3.27.2、hooks_riverpod、media_kit、window_manager、shared_preferences（新增）。

## Global Constraints

- 干净名仅用于显示，**绝不修改磁盘文件名/文件夹名**。
- 噪声匹配 = 内置智能规则（可逐项开关，默认全开）+ 用户自定义文字片段（字面子串，大小写不敏感）。
- 集号/季解析始终基于**原始**文件名（`EpisodeSorter.parse`），清洗不得影响集号识别。
- 持久化用 `shared_preferences`，键 `name_clean_config_v1`，存 JSON 字符串；解析失败回退默认配置。
- 分组键 = 识别出的剧名；剧名为空或纯数字时回退**父文件夹名**（经同样清洗）。
- 只新增一个"配置"按钮；**配置保存即自动重新生成显示名与分组**（无独立"重命名"按钮）。
- 跨组连播：自动连播到组末尾后继续下一组（依赖扁平全局顺序天然实现）。
- 每个任务结束跑 `flutter test`（基线 38/38 全绿）与 `flutter analyze`（0 issue）。

---

### Task 0: 新增 shared_preferences 依赖

**Files:**
- Modify: `pubspec.yaml`、`pubspec.lock`
- Modify（构建自动重生成）: `macos/Flutter/GeneratedPluginRegistrant.swift`、`linux/flutter/generated_plugin_registrant.cc`、`linux/flutter/generated_plugins.cmake`、`windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`

**Interfaces:**
- Produces: 项目可 `import 'package:shared_preferences/shared_preferences.dart';`

- [ ] **Step 1: 添加依赖**

Run: `flutter pub add shared_preferences`
Expected: pubspec.yaml 出现 `shared_preferences: ^2.x`，pub get 成功。

- [ ] **Step 2: 触发各桌面平台插件注册重生成**

Run: `flutter build macos --debug 2>&1 | tail -3`
Expected: `✓ Built ...jump_player.app`；`macos/Flutter/GeneratedPluginRegistrant.swift` 出现 `import shared_preferences_foundation`（`git diff --stat` 可见生成文件变化）。

- [ ] **Step 3: 确认基线测试仍全绿**

Run: `flutter test`
Expected: All tests passed（基线 38）。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock macos linux windows
git commit -m "build: add shared_preferences dependency"
```

---

### Task 1: NameCleanConfig + BuiltinNoiseRule（配置模型）

**Files:**
- Create: `lib/domain/library/name_clean_config.dart`
- Test: `test/domain/library/name_clean_config_test.dart`

**Interfaces:**
- Produces:
  - `enum BuiltinNoiseRule { bracketGroups, parenGroups, resolution, codecSource, year }`
  - `class NameCleanConfig { final Set<BuiltinNoiseRule> enabledBuiltinRules; final List<String> customSnippets; static const NameCleanConfig defaults; NameCleanConfig copyWith({...}); Map<String,dynamic> toJson(); factory NameCleanConfig.fromJson(Map<String,dynamic>); String encode(); factory NameCleanConfig.decode(String); }`

- [ ] **Step 1: 写失败测试**

```dart
// test/domain/library/name_clean_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';

void main() {
  test('defaults 启用全部内置规则且无自定义片段', () {
    expect(NameCleanConfig.defaults.enabledBuiltinRules,
        BuiltinNoiseRule.values.toSet());
    expect(NameCleanConfig.defaults.customSnippets, isEmpty);
  });

  test('encode/decode 往返保持数据', () {
    const cfg = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.bracketGroups, BuiltinNoiseRule.year},
      customSnippets: ['HD国语中字无水印', '最新电影www.dyg7.com'],
    );
    final back = NameCleanConfig.decode(cfg.encode());
    expect(back.enabledBuiltinRules,
        {BuiltinNoiseRule.bracketGroups, BuiltinNoiseRule.year});
    expect(back.customSnippets, ['HD国语中字无水印', '最新电影www.dyg7.com']);
  });

  test('decode 非法字符串回退 defaults', () {
    expect(NameCleanConfig.decode('not json').enabledBuiltinRules,
        BuiltinNoiseRule.values.toSet());
  });

  test('fromJson 忽略未知规则名', () {
    final cfg = NameCleanConfig.fromJson({
      'enabledBuiltinRules': ['bracketGroups', 'somethingNew'],
      'customSnippets': <String>[],
    });
    expect(cfg.enabledBuiltinRules, {BuiltinNoiseRule.bracketGroups});
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/library/name_clean_config_test.dart`
Expected: FAIL（`name_clean_config.dart` 不存在 / 类型未定义）。

- [ ] **Step 3: 实现**

```dart
// lib/domain/library/name_clean_config.dart
import 'dart:convert';

enum BuiltinNoiseRule {
  bracketGroups,
  parenGroups,
  resolution,
  codecSource,
  year,
}

class NameCleanConfig {
  const NameCleanConfig({
    required this.enabledBuiltinRules,
    required this.customSnippets,
  });

  final Set<BuiltinNoiseRule> enabledBuiltinRules;
  final List<String> customSnippets;

  static const NameCleanConfig defaults = NameCleanConfig(
    enabledBuiltinRules: {
      BuiltinNoiseRule.bracketGroups,
      BuiltinNoiseRule.parenGroups,
      BuiltinNoiseRule.resolution,
      BuiltinNoiseRule.codecSource,
      BuiltinNoiseRule.year,
    },
    customSnippets: <String>[],
  );

  NameCleanConfig copyWith({
    Set<BuiltinNoiseRule>? enabledBuiltinRules,
    List<String>? customSnippets,
  }) {
    return NameCleanConfig(
      enabledBuiltinRules: enabledBuiltinRules ?? this.enabledBuiltinRules,
      customSnippets: customSnippets ?? this.customSnippets,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledBuiltinRules':
            enabledBuiltinRules.map((r) => r.name).toList(),
        'customSnippets': customSnippets,
      };

  factory NameCleanConfig.fromJson(Map<String, dynamic> json) {
    final names = (json['enabledBuiltinRules'] as List?)?.cast<String>() ??
        const <String>[];
    final rules = <BuiltinNoiseRule>{};
    for (final name in names) {
      for (final r in BuiltinNoiseRule.values) {
        if (r.name == name) rules.add(r);
      }
    }
    final snippets =
        (json['customSnippets'] as List?)?.cast<String>() ?? const <String>[];
    return NameCleanConfig(
      enabledBuiltinRules: rules,
      customSnippets: List<String>.from(snippets),
    );
  }

  String encode() => jsonEncode(toJson());

  factory NameCleanConfig.decode(String source) {
    try {
      return NameCleanConfig.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
    } catch (_) {
      return defaults;
    }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/domain/library/name_clean_config_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/domain/library/name_clean_config.dart test/domain/library/name_clean_config_test.dart
git commit -m "feat: add NameCleanConfig with built-in noise rules"
```

---

### Task 2: NameCleaner（清洗引擎，纯函数）

**Files:**
- Create: `lib/domain/library/name_cleaner.dart`
- Test: `test/domain/library/name_cleaner_test.dart`

**Interfaces:**
- Consumes: `EpisodeSorter.parse(String)`（已存在）、`NameCleanConfig`、`BuiltinNoiseRule`（Task 1）
- Produces:
  - `class CleanedName { final String displayName; final String seriesTitle; final int? season; final int? episodeNumber; }`
  - `class NameCleaner { static CleanedName clean(String fileName, String parentDirName, NameCleanConfig config); static String cleanDir(String dirName, NameCleanConfig config); }`

- [ ] **Step 1: 写失败测试**

```dart
// test/domain/library/name_cleaner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/library/name_cleaner.dart';

void main() {
  const cfg = NameCleanConfig.defaults;

  test('括号包裹的剧名被默认规则清空 → 回退父文件夹名', () {
    final r = NameCleaner.clean(
        '[GM-Team][国漫][逆天邪神 第2季][AgeFans][01][2160p].mp4', '逆天邪神', cfg);
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '逆天邪神');
    expect(r.displayName, '逆天邪神 01');
  });

  test('中文第N集：集号被剥离、季号保留', () {
    final r = NameCleaner.clean('逆天邪神 第2季 第05集.mp4', 'Downloads', cfg);
    expect(r.episodeNumber, 5);
    expect(r.seriesTitle, '逆天邪神 第2季');
    expect(r.displayName, '逆天邪神 第2季 05');
  });

  test('无剧名只剩集号 + 自定义片段 → 回退父文件夹名', () {
    final c = cfg.copyWith(customSnippets: ['HD国语中字无水印']);
    final r = NameCleaner.clean(
        '01.2160p.HD国语中字无水印[最新电影www.dyg7.com].mkv', '成何体统', c);
    expect(r.episodeNumber, 1);
    expect(r.seriesTitle, '成何体统');
    expect(r.displayName, '成何体统 01');
  });

  test('无集号：displayName 为清洗后的 stem', () {
    final r = NameCleaner.clean('阿凡达.mkv', '电影', cfg);
    expect(r.episodeNumber, isNull);
    expect(r.seriesTitle, '阿凡达');
    expect(r.displayName, '阿凡达');
  });

  test('cleanDir 去噪并归一化', () {
    expect(NameCleaner.cleanDir('[国漫]逆天邪神', cfg), '逆天邪神');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/library/name_cleaner_test.dart`
Expected: FAIL（`name_cleaner.dart` 不存在）。

- [ ] **Step 3: 实现**

```dart
// lib/domain/library/name_cleaner.dart
import 'package:jump_player/domain/library/episode_sorter.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';

class CleanedName {
  const CleanedName({
    required this.displayName,
    required this.seriesTitle,
    this.season,
    this.episodeNumber,
  });

  final String displayName;
  final String seriesTitle;
  final int? season;
  final int? episodeNumber;
}

class NameCleaner {
  static final Map<BuiltinNoiseRule, RegExp> _rulePatterns = {
    BuiltinNoiseRule.bracketGroups: RegExp(r'\[[^\]]*\]'),
    BuiltinNoiseRule.parenGroups: RegExp(r'\([^)]*\)'),
    BuiltinNoiseRule.resolution: RegExp(
        r'\b\d{3,4}[pi]\b|\b(?:4k|2k|2160p|1080p|720p|480p)\b',
        caseSensitive: false),
    BuiltinNoiseRule.codecSource: RegExp(
        r'\b(?:x264|x265|h\.?264|h\.?265|hevc|avc|aac|flac'
        r'|web-?rip|web-?dl|webdl|bluray|bdrip|dts|ddp?5?\.?1)\b',
        caseSensitive: false),
    BuiltinNoiseRule.year: RegExp(r'\b(?:19|20)\d{2}\b'),
  };

  // 派生剧名时剥离的集号 token（不盲删裸数字，以保护「第2季」等）。
  static final List<RegExp> _episodeTokens = [
    RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}'),
    RegExp(r'第\s*\d{1,4}\s*[集話话期]'),
    RegExp(r'\d{1,4}\s*[集話话期]'),
    RegExp(r'\b[Ee][Pp]?\d{1,4}\b'),
    RegExp(r'\[\d{1,3}\]'),
  ];

  static final RegExp _separators = RegExp(r'[\s._\-]+');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static String _stem(String name) =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  static String _applyRules(String input, NameCleanConfig config) {
    var s = input;
    for (final rule in BuiltinNoiseRule.values) {
      if (config.enabledBuiltinRules.contains(rule)) {
        s = s.replaceAll(_rulePatterns[rule]!, ' ');
      }
    }
    for (final snippet in config.customSnippets) {
      if (snippet.isEmpty) continue;
      s = s.replaceAll(
          RegExp(RegExp.escape(snippet), caseSensitive: false), ' ');
    }
    return s;
  }

  static String _normalize(String input) =>
      input.replaceAll(_separators, ' ').trim();

  static String _stripEpisodeTokens(String input) {
    var s = input;
    for (final re in _episodeTokens) {
      s = s.replaceAll(re, ' ');
    }
    return _normalize(s);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String cleanDir(String dirName, NameCleanConfig config) {
    final cleaned = _normalize(_applyRules(_stem(dirName), config));
    return cleaned.isEmpty ? dirName : cleaned;
  }

  static CleanedName clean(
    String fileName,
    String parentDirName,
    NameCleanConfig config,
  ) {
    final parsed = EpisodeSorter.parse(fileName); // 基于原始文件名
    final stem = _stem(fileName);
    final cleanedStem = _normalize(_applyRules(stem, config));

    var title = _stripEpisodeTokens(cleanedStem);
    if (title.isEmpty || _digitsOnly.hasMatch(title)) {
      title = cleanDir(parentDirName, config);
    }
    if (title.isEmpty) title = stem;

    final ep = parsed?.episode;
    final String displayName;
    if (ep != null) {
      displayName = '$title ${_pad(ep)}';
    } else {
      displayName = cleanedStem.isEmpty ? stem : cleanedStem;
    }

    return CleanedName(
      displayName: displayName,
      seriesTitle: title,
      season: parsed?.season,
      episodeNumber: ep,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/domain/library/name_cleaner_test.dart`
Expected: PASS（5 个用例全绿）。

- [ ] **Step 5: Commit**

```bash
git add lib/domain/library/name_cleaner.dart test/domain/library/name_cleaner_test.dart
git commit -m "feat: add NameCleaner for non-destructive display names"
```

---

### Task 3: PreferencesConfigStore（持久化）

**Files:**
- Create: `lib/infra/config/preferences_config_store.dart`
- Test: `test/infra/config/preferences_config_store_test.dart`

**Interfaces:**
- Consumes: `NameCleanConfig`（Task 1）、`shared_preferences`（Task 0）
- Produces: `class PreferencesConfigStore { Future<NameCleanConfig> load(); Future<void> save(NameCleanConfig config); }`

- [ ] **Step 1: 写失败测试**

```dart
// test/infra/config/preferences_config_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/infra/config/preferences_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无存储值时 load 返回 defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesConfigStore();
    final cfg = await store.load();
    expect(cfg.enabledBuiltinRules, BuiltinNoiseRule.values.toSet());
  });

  test('save 后 load 往返一致', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesConfigStore();
    const cfg = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.resolution},
      customSnippets: ['最新电影www.dyg7.com'],
    );
    await store.save(cfg);
    final back = await store.load();
    expect(back.enabledBuiltinRules, {BuiltinNoiseRule.resolution});
    expect(back.customSnippets, ['最新电影www.dyg7.com']);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/infra/config/preferences_config_store_test.dart`
Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现**

```dart
// lib/infra/config/preferences_config_store.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';

class PreferencesConfigStore {
  static const String _key = 'name_clean_config_v1';

  Future<NameCleanConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return NameCleanConfig.defaults;
    return NameCleanConfig.decode(raw);
  }

  Future<void> save(NameCleanConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.encode());
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/infra/config/preferences_config_store_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/infra/config/preferences_config_store.dart test/infra/config/preferences_config_store_test.dart
git commit -m "feat: persist NameCleanConfig via shared_preferences"
```

---

### Task 4: 模型分组化 + Scanner 产出分组

**Files:**
- Modify: `lib/domain/library/library_models.dart`
- Modify: `lib/domain/library/library_scanner.dart`
- Test: `test/domain/library/library_models_test.dart`、`test/domain/library/library_scanner_test.dart`
- Modify（修构造点保持绿）: `test/state/playback_queue_test.dart`、`test/state/library_actions_test.dart`、`test/ui/episode_sidebar_test.dart`、`test/ui/player_page_test.dart`、`test/ui/control_bar_test.dart`（仅其中实际构造 `Series` 的文件需要改）

**Interfaces:**
- Consumes: `NameCleaner.clean(...)`（Task 2）、`NameCleanConfig.defaults`（Task 1）
- Produces:
  - `class Episode { Episode({required path, required fileName, String? displayName, season, episodeNumber}); final String path, fileName, displayName; final int? season, episodeNumber; }`
  - `class SeriesGroup { const SeriesGroup({required String title, required List<Episode> episodes}); }`
  - `class Series { const Series({required String name, required String rootPath, required List<SeriesGroup> groups}); List<Episode> get episodes; }`
  - `Future<Series> LibraryScanner.scan(String rootPath, [NameCleanConfig config = NameCleanConfig.defaults])`

- [ ] **Step 1: 写失败测试（模型）**

```dart
// test/domain/library/library_models_test.dart  —— 整文件替换
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_models.dart';

void main() {
  test('Episode.displayName 缺省回退 fileName', () {
    final e = Episode(path: '/a/x.mkv', fileName: 'x.mkv');
    expect(e.displayName, 'x.mkv');
  });

  test('Episode 相等基于 path', () {
    final a = Episode(path: '/a', fileName: 'a', displayName: 'A');
    final b = Episode(path: '/a', fileName: 'b', displayName: 'B');
    expect(a, b);
  });

  test('Series.episodes 展平所有组', () {
    const s = Series(name: 's', rootPath: '/s', groups: [
      SeriesGroup(title: 'g1', episodes: [
        Episode2('/1'),
      ]),
      SeriesGroup(title: 'g2', episodes: [
        Episode2('/2'),
        Episode2('/3'),
      ]),
    ]);
    expect(s.episodes.map((e) => e.path), ['/1', '/2', '/3']);
  });
}

// 测试辅助：const 友好的 Episode 构造
class Episode2 extends Episode {
  Episode2(String p) : super(path: p, fileName: p);
}
```

> 注：`Series`/`SeriesGroup` 为 const 构造，但 `Episode` 因 `displayName ?? fileName` 初始化不可 const；上面用非 const 列表即可，去掉 `const` 关键字。把第三个测试写成：

```dart
  test('Series.episodes 展平所有组', () {
    final s = Series(name: 's', rootPath: '/s', groups: [
      SeriesGroup(title: 'g1', episodes: [Episode(path: '/1', fileName: '1')]),
      SeriesGroup(title: 'g2', episodes: [
        Episode(path: '/2', fileName: '2'),
        Episode(path: '/3', fileName: '3'),
      ]),
    ]);
    expect(s.episodes.map((e) => e.path), ['/1', '/2', '/3']);
  });
```

（采用此版本，删除 `Episode2` 辅助类与前一个写法。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/library/library_models_test.dart`
Expected: FAIL（`SeriesGroup` 未定义 / `Series.groups` 不存在）。

- [ ] **Step 3: 实现模型**

```dart
// lib/domain/library/library_models.dart  —— 整文件替换
class Episode {
  Episode({
    required this.path,
    required this.fileName,
    String? displayName,
    this.season,
    this.episodeNumber,
  }) : displayName = displayName ?? fileName;

  final String path;
  final String fileName;
  final String displayName;
  final int? season;
  final int? episodeNumber;

  @override
  bool operator ==(Object other) => other is Episode && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class SeriesGroup {
  const SeriesGroup({required this.title, required this.episodes});

  final String title;
  final List<Episode> episodes;
}

class Series {
  const Series({
    required this.name,
    required this.rootPath,
    required this.groups,
  });

  final String name;
  final String rootPath;
  final List<SeriesGroup> groups;

  List<Episode> get episodes => [for (final g in groups) ...g.episodes];
}
```

- [ ] **Step 4: 写失败测试（scanner 分组）**

```dart
// test/domain/library/library_scanner_test.dart  —— 整文件替换
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/library/library_scanner.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File touch(String name) => File('${tmp.path}/$name')..writeAsStringSync('x');

  test('按识别出的剧名分组、组内按集号排序', () async {
    touch('逆天邪神 第2季 第02集.mp4');
    touch('逆天邪神 第2季 第10集.mp4');
    touch('逆天邪神 第2季 第01集.mp4');
    touch('成何体统 第01集.mp4');

    final series = await LibraryScanner().scan(tmp.path);
    final titles = series.groups.map((g) => g.title).toList();
    expect(titles, containsAll(['逆天邪神 第2季', '成何体统']));

    final ntx = series.groups.firstWhere((g) => g.title == '逆天邪神 第2季');
    expect(ntx.episodes.map((e) => e.episodeNumber), [1, 2, 10]);
    expect(ntx.episodes.first.displayName, '逆天邪神 第2季 01');
  });

  test('只有视频扩展名被收录', () async {
    touch('a 第01集.mp4');
    touch('note.txt');
    final series = await LibraryScanner().scan(tmp.path);
    expect(series.episodes.length, 1);
  });
}
```

- [ ] **Step 5: 跑测试确认失败**

Run: `flutter test test/domain/library/library_scanner_test.dart`
Expected: FAIL（`scan` 返回结构不含 groups / 编译错误）。

- [ ] **Step 6: 实现 scanner**

```dart
// lib/domain/library/library_scanner.dart  —— 整文件替换
import 'dart:io';

import 'package:jump_player/domain/library/episode_sorter.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/library/name_cleaner.dart';

class LibraryScanner {
  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.flv', '.ts',
    '.webm', '.m4v', '.wmv', '.rmvb', '.rm', '.mpg', '.mpeg',
  };

  Future<Series> scan(
    String rootPath, [
    NameCleanConfig config = NameCleanConfig.defaults,
  ]) async {
    final root = Directory(rootPath);
    final groupsMap = <String, List<Episode>>{};

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      final ext = _extension(name).toLowerCase();
      if (!videoExtensions.contains(ext)) continue;

      final parentDir = _baseName(_parentPath(entity.path));
      final cleaned = NameCleaner.clean(name, parentDir, config);
      final episode = Episode(
        path: entity.path,
        fileName: name,
        displayName: cleaned.displayName,
        season: cleaned.season,
        episodeNumber: cleaned.episodeNumber,
      );
      groupsMap.putIfAbsent(cleaned.seriesTitle, () => []).add(episode);
    }

    final titles = groupsMap.keys.toList()
      ..sort(EpisodeSorter.compareNatural);
    final groups = [
      for (final t in titles)
        SeriesGroup(title: t, episodes: EpisodeSorter.sort(groupsMap[t]!)),
    ];

    return Series(name: _baseName(rootPath), rootPath: rootPath, groups: groups);
  }

  static String _baseName(String path) {
    final norm = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final idxForward = norm.lastIndexOf('/');
    final idxBack = norm.lastIndexOf('\\');
    final idx = idxForward > idxBack ? idxForward : idxBack;
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _parentPath(String path) {
    final norm = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final idxForward = norm.lastIndexOf('/');
    final idxBack = norm.lastIndexOf('\\');
    final idx = idxForward > idxBack ? idxForward : idxBack;
    return idx >= 0 ? norm.substring(0, idx) : norm;
  }

  static String _extension(String name) {
    final idx = name.lastIndexOf('.');
    return idx >= 0 ? name.substring(idx) : '';
  }
}
```

- [ ] **Step 7: 修复其余因模型变更而编译失败的测试**

Run: `flutter test 2>&1 | grep -A2 -iE "error|Series|episodes" | head -40`
逐个把构造 `Series(name:..., rootPath:..., episodes:[...])` 的旧测试改为分组写法。在每个受影响的测试文件顶部加私有辅助并替换构造点：

```dart
// 放在该测试文件 main() 之上
Series singleGroupSeries(List<Episode> eps, {String name = 's'}) => Series(
      name: name,
      rootPath: '/$name',
      groups: [SeriesGroup(title: name, episodes: eps)],
    );
```

把旧的 `Series(name: 's', rootPath: '/s', episodes: eps)` 替换为 `singleGroupSeries(eps)`。
（`PlaybackQueue` 仅用 `series.episodes` getter，逻辑不变；这些改动只发生在测试文件。）

- [ ] **Step 8: 跑全量测试确认全绿**

Run: `flutter test`
Expected: All tests passed（含新增的 models/scanner 用例）。

- [ ] **Step 9: analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 10: Commit**

```bash
git add lib/domain/library test/
git commit -m "feat: group library by recognized series title"
```

---

### Task 5: 配置 providers + library_actions 接线（保存即刷新）

**Files:**
- Create: `lib/state/name_clean_providers.dart`
- Modify: `lib/state/library_actions.dart`
- Test: `test/state/name_clean_providers_test.dart`、`test/state/library_actions_test.dart`

**Interfaces:**
- Consumes: `PreferencesConfigStore`（Task 3）、`NameCleanConfig`（Task 1）、`LibraryScanner.scan(path, config)`（Task 4）、`playbackQueueProvider`（已存在）
- Produces:
  - `final configStoreProvider = Provider<PreferencesConfigStore>(...)`
  - `final nameCleanConfigProvider = StateNotifierProvider<NameCleanConfigController, NameCleanConfig>(...)`
  - `class NameCleanConfigController extends StateNotifier<NameCleanConfig> { Future<void> save(NameCleanConfig); }`
  - `LibraryActions.openFolder(String)`（不变签名，内部读 config）、新增 `Future<void> reapplyCurrent()`

- [ ] **Step 1: 写失败测试（providers）**

```dart
// test/state/name_clean_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/name_clean_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save 更新 state 并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const next = NameCleanConfig(
      enabledBuiltinRules: {BuiltinNoiseRule.year},
      customSnippets: ['x'],
    );
    await container.read(nameCleanConfigProvider.notifier).save(next);
    expect(container.read(nameCleanConfigProvider).customSnippets, ['x']);

    // 新容器从持久化读回
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c2.read(nameCleanConfigProvider.notifier).debugLoadedSnippets(),
        completion(['x']));
  });
}
```

> `debugLoadedSnippets()` 是 controller 暴露的测试便捷方法（见实现），返回 store.load() 的 customSnippets，避免依赖异步初始化时序。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/state/name_clean_providers_test.dart`
Expected: FAIL（providers 不存在）。

- [ ] **Step 3: 实现 providers**

```dart
// lib/state/name_clean_providers.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/infra/config/preferences_config_store.dart';

final configStoreProvider =
    Provider<PreferencesConfigStore>((ref) => PreferencesConfigStore());

class NameCleanConfigController extends StateNotifier<NameCleanConfig> {
  NameCleanConfigController(this._store) : super(NameCleanConfig.defaults) {
    _load();
  }

  final PreferencesConfigStore _store;

  Future<void> _load() async {
    state = await _store.load();
  }

  Future<void> save(NameCleanConfig config) async {
    state = config;
    await _store.save(config);
  }

  Future<List<String>> debugLoadedSnippets() async =>
      (await _store.load()).customSnippets;
}

final nameCleanConfigProvider =
    StateNotifierProvider<NameCleanConfigController, NameCleanConfig>((ref) {
  return NameCleanConfigController(ref.watch(configStoreProvider));
});
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/state/name_clean_providers_test.dart`
Expected: PASS。

- [ ] **Step 5: 写失败测试（library_actions reapply）**

在 `test/state/library_actions_test.dart` 增补（保留现有用例，按 Task 4 的辅助构造调整后）。新增：

```dart
  test('reapplyCurrent 用最新配置重扫并保留当前播放项', () async {
    // 详见现有测试的 fake scanner 模式：注入一个按 config 返回不同分组的 fake。
    // 断言：改 config 后 reapplyCurrent() 使 queue.state.series 反映新分组，
    // 且 currentEpisode.path 不变（若仍存在）。
    // （此用例需要一个可控的 FakeScanner；沿用文件中既有 Fake 风格实现。）
  });
```

> 实施者注：若现有 `library_actions_test.dart` 使用真实 `LibraryScanner` + 临时目录，则改 config 前后各放置不同噪声的文件名，验证 `reapplyCurrent()` 后 `ref.read(playbackQueueProvider).series` 的组标题变化、且 `currentEpisode?.path` 在仍存在时保持不变。

- [ ] **Step 6: 实现 library_actions 接线**

```dart
// lib/state/library_actions.dart  —— 整文件替换
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/library_scanner.dart';
import 'package:jump_player/state/name_clean_providers.dart';
import 'package:jump_player/state/playback_queue.dart';

class LibraryActions {
  LibraryActions(this._scanner, this._ref);

  final LibraryScanner _scanner;
  final Ref _ref;
  String? _currentRoot;

  PlaybackQueueController get _queue =>
      _ref.read(playbackQueueProvider.notifier);

  Future<void> openFolder(String path) async {
    final config = _ref.read(nameCleanConfigProvider);
    final series = await _scanner.scan(path, config);
    _currentRoot = path;
    await _queue.loadSeries(series);
  }

  Future<void> reapplyCurrent() async {
    final root = _currentRoot;
    if (root == null) return;
    final config = _ref.read(nameCleanConfigProvider);
    final currentPath =
        _ref.read(playbackQueueProvider).currentEpisode?.path;
    final series = await _scanner.scan(root, config);
    final startAt = _flatIndexOfPath(series, currentPath);
    await _queue.loadSeries(series, startAt: startAt);
  }

  int _flatIndexOfPath(Series series, String? path) {
    if (path == null) return 0;
    final eps = series.episodes;
    final i = eps.indexWhere((e) => e.path == path);
    return i < 0 ? 0 : i;
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(LibraryScanner(), ref);
});
```

> 注意：`libraryActionsProvider` 现在依赖 `ref`（而非预先 `watch` queue notifier），因此其测试需在 `ProviderContainer` 内 `read(libraryActionsProvider)`。按此调整现有 `library_actions_test.dart` 的获取方式。

- [ ] **Step 7: 跑全量测试 + analyze**

Run: `flutter test && flutter analyze`
Expected: All tests passed；No issues found.

- [ ] **Step 8: Commit**

```bash
git add lib/state/name_clean_providers.dart lib/state/library_actions.dart test/state/
git commit -m "feat: wire config providers and re-apply on save"
```

---

### Task 6: 命名配置对话框

**Files:**
- Create: `lib/ui/name_clean_config_dialog.dart`
- Test: `test/ui/name_clean_config_dialog_test.dart`

**Interfaces:**
- Consumes: `nameCleanConfigProvider`、`libraryActionsProvider`（Task 5）、`BuiltinNoiseRule`/`NameCleanConfig`（Task 1）
- Produces: `Future<void> showNameCleanConfigDialog(BuildContext context, WidgetRef ref)`；`class NameCleanConfigDialog extends ConsumerStatefulWidget`

- [ ] **Step 1: 写失败测试**

```dart
// test/ui/name_clean_config_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/name_clean_providers.dart';
import 'package:jump_player/ui/name_clean_config_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('展示内置规则开关并能添加自定义片段后保存', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: NameCleanConfigDialog())),
    ));
    await tester.pumpAndSettle();

    // 每个内置规则一个开关
    expect(find.byType(SwitchListTile), findsNWidgets(BuiltinNoiseRule.values.length));

    // 添加一个自定义片段
    await tester.enterText(find.byKey(const Key('snippet-input')), 'HD国语中字无水印');
    await tester.tap(find.byKey(const Key('snippet-add')));
    await tester.pump();
    expect(find.text('HD国语中字无水印'), findsOneWidget);

    // 保存
    await tester.tap(find.byKey(const Key('config-save')));
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/name_clean_config_dialog_test.dart`
Expected: FAIL（文件不存在）。

- [ ] **Step 3: 实现对话框**

```dart
// lib/ui/name_clean_config_dialog.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/state/name_clean_providers.dart';

const Map<BuiltinNoiseRule, String> kRuleLabels = {
  BuiltinNoiseRule.bracketGroups: '方括号组 […]',
  BuiltinNoiseRule.parenGroups: '圆括号组 (…)',
  BuiltinNoiseRule.resolution: '分辨率（1080p/2160p…）',
  BuiltinNoiseRule.codecSource: '编码/来源（x265/WEB-DL/BluRay…）',
  BuiltinNoiseRule.year: '年份（19xx/20xx）',
};

Future<void> showNameCleanConfigDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: NameCleanConfigDialog()),
  );
}

class NameCleanConfigDialog extends ConsumerStatefulWidget {
  const NameCleanConfigDialog({super.key});

  @override
  ConsumerState<NameCleanConfigDialog> createState() =>
      _NameCleanConfigDialogState();
}

class _NameCleanConfigDialogState extends ConsumerState<NameCleanConfigDialog> {
  late Set<BuiltinNoiseRule> _rules;
  late List<String> _snippets;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(nameCleanConfigProvider);
    _rules = {...cfg.enabledBuiltinRules};
    _snippets = [...cfg.customSnippets];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addSnippet() {
    final v = _input.text.trim();
    if (v.isEmpty || _snippets.contains(v)) return;
    setState(() {
      _snippets.add(v);
      _input.clear();
    });
  }

  Future<void> _save() async {
    final cfg = NameCleanConfig(
      enabledBuiltinRules: _rules,
      customSnippets: _snippets,
    );
    await ref.read(nameCleanConfigProvider.notifier).save(cfg);
    await ref.read(libraryActionsProvider).reapplyCurrent();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('命名清洗配置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final rule in BuiltinNoiseRule.values)
                  SwitchListTile(
                    title: Text(kRuleLabels[rule]!),
                    value: _rules.contains(rule),
                    onChanged: (on) => setState(() {
                      on ? _rules.add(rule) : _rules.remove(rule);
                    }),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('snippet-input'),
                        controller: _input,
                        decoration: const InputDecoration(
                            hintText: '自定义噪声文字，如 HD国语中字无水印'),
                        onSubmitted: (_) => _addSnippet(),
                      ),
                    ),
                    IconButton(
                      key: const Key('snippet-add'),
                      icon: const Icon(Icons.add),
                      onPressed: _addSnippet,
                    ),
                  ]),
                ),
                for (final s in _snippets)
                  ListTile(
                    dense: true,
                    title: Text(s),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _snippets.remove(s)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('config-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/name_clean_config_dialog_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/ui/name_clean_config_dialog.dart test/ui/name_clean_config_dialog_test.dart
git commit -m "feat: name-clean config dialog"
```

---

### Task 7: 控制栏并入剧集列表按钮 + 配置按钮；移除浮动按钮

**Files:**
- Modify: `lib/ui/control_bar.dart`
- Modify: `lib/ui/player_page.dart`
- Test: `test/ui/control_bar_test.dart`、`test/ui/player_page_test.dart`

**Interfaces:**
- Consumes: `sidebarVisibleProvider`（已存在）、`showNameCleanConfigDialog`（Task 6）
- Produces: 控制栏含 tooltip 为 `剧集列表` 与 `命名配置` 的两枚按钮；`player_page` 不再有浮动按钮。

- [ ] **Step 1: 写失败测试**

```dart
// 追加到 test/ui/control_bar_test.dart
  testWidgets('控制栏含剧集列表与命名配置按钮', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ControlBar())),
    ));
    expect(find.byTooltip('剧集列表'), findsOneWidget);
    expect(find.byTooltip('命名配置'), findsOneWidget);
  });
```

```dart
// 修改 test/ui/player_page_test.dart 的断言：浮动按钮已移除
  testWidgets('player_page 不再有浮动剧集列表按钮（按钮在控制栏内）', (tester) async {
    // 原断言若检查 Positioned 中的 playlist_play，改为：控制栏存在该 tooltip，
    // 且 Stack 顶层不存在 Positioned(top:8,left:8) 的 IconButton。
    // 最小校验：find.byTooltip('剧集列表') 命中 1 个（位于控制栏）。
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/control_bar_test.dart`
Expected: FAIL（找不到 `命名配置` tooltip）。

- [ ] **Step 3: 修改 control_bar（在"下一集"与"全屏"之间插入剧集列表与配置按钮）**

在 `lib/ui/control_bar.dart`：新增 import：

```dart
import 'package:jump_player/state/ui_providers.dart';
import 'package:jump_player/ui/name_clean_config_dialog.dart';
```

在"打开文件夹"按钮之后插入"剧集列表"按钮：

```dart
          IconButton(
            tooltip: '剧集列表',
            color: Colors.white,
            icon: const Icon(Icons.playlist_play),
            onPressed: () => ref.read(sidebarVisibleProvider.notifier).state =
                !ref.read(sidebarVisibleProvider),
          ),
```

在"下一集"按钮之后、"全屏"按钮之前插入"配置"按钮：

```dart
          IconButton(
            tooltip: '命名配置',
            color: Colors.white,
            icon: const Icon(Icons.tune),
            onPressed: () => showNameCleanConfigDialog(context),
          ),
```

- [ ] **Step 4: 修改 player_page 移除浮动按钮**

在 `lib/ui/player_page.dart` 删除 `Positioned(top:8,left:8, child: IconButton(... Icons.playlist_play ...))` 整块；保留 `Video` 与侧边栏 `Align`。移除随之不再使用的 import（若 `ui_providers` 仍被 `sidebarVisibleProvider` 使用则保留）。

- [ ] **Step 5: 跑测试确认通过 + analyze**

Run: `flutter test test/ui/control_bar_test.dart test/ui/player_page_test.dart && flutter analyze`
Expected: PASS；No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/control_bar.dart lib/ui/player_page.dart test/ui/
git commit -m "feat: move playlist toggle into control bar, add config button"
```

---

### Task 8: 侧边栏分组展示

**Files:**
- Modify: `lib/ui/episode_sidebar.dart`
- Test: `test/ui/episode_sidebar_test.dart`

**Interfaces:**
- Consumes: `playbackQueueProvider`（state 含 `series.groups`）、`PlaybackQueueController.playAt(int)`（已存在，按全局索引）
- Produces: 分组渲染；点击换算全局索引并 `playAt`；显示 `episode.displayName`。

- [ ] **Step 1: 写失败测试**

```dart
// test/ui/episode_sidebar_test.dart  —— 关键新增/调整
  testWidgets('分组渲染：组标题 + 干净显示名，点击播放对应全局索引', (tester) async {
    // 载入一个含两组的 Series：g1[ep01,ep02], g2[ep01]
    // 断言：find.text('逆天邪神 第2季') 命中（组标题）
    //       find.text('逆天邪神 第2季 01') 命中（displayName）
    // 点击 g2 的第一项 → 期望 playAt(2)（全局索引 = 0+1 组前缀 2）
  });
```

> 实施者注：沿用文件现有的 fake/engine 注入方式构造 `Series(groups:[...])` 并 `loadSeries`。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/episode_sidebar_test.dart`
Expected: FAIL（仍是扁平 ListView，找不到组标题）。

- [ ] **Step 3: 实现分组侧边栏**

```dart
// lib/ui/episode_sidebar.dart  —— 整文件替换
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_queue.dart';

class EpisodeSidebar extends ConsumerWidget {
  const EpisodeSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackQueueProvider);
    final controller = ref.read(playbackQueueProvider.notifier);
    final groups = state.series?.groups ?? const [];

    final rows = <Widget>[];
    var globalIndex = 0;
    for (final group in groups) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(
          group.title,
          style: const TextStyle(
              color: Colors.white70, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ));
      for (final ep in group.episodes) {
        final idx = globalIndex;
        final selected = idx == state.currentIndex;
        rows.add(ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: Colors.white24,
          title: Text(
            ep.displayName,
            style: TextStyle(color: selected ? Colors.amber : Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => controller.playAt(idx),
        ));
        globalIndex++;
      }
    }

    return Container(
      width: 280,
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              state.series?.name ?? '未载入剧集',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(children: rows)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过 + analyze**

Run: `flutter test test/ui/episode_sidebar_test.dart && flutter analyze`
Expected: PASS；No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/episode_sidebar.dart test/ui/episode_sidebar_test.dart
git commit -m "feat: grouped episode sidebar with clean display names"
```

---

### Task 9: 全量验收（测试 / 分析 / 构建 / 手测清单）

**Files:** 无（验证任务）

- [ ] **Step 1: 全量测试**

Run: `flutter test`
Expected: All tests passed（基线 38 + 本次新增用例）。

- [ ] **Step 2: 静态分析**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: 构建并运行 macOS**

Run: `flutter build macos --debug 2>&1 | tail -3 && open build/macos/Build/Products/Debug/jump_player.app`
Expected: 构建成功；应用启动。

- [ ] **Step 4: 手测清单（截图核对）**

- 打开文件夹后，列表按**组**展示，标题为识别出的剧名，集目显示**干净名**。
- 底部控制栏顺序：`打开文件 · 打开文件夹 · 剧集列表 · ⏮ · ⏯ · ⏭ · 命名配置 · 全屏`；画面左上角**无**浮动按钮。
- 点"命名配置"→ 切换规则 / 添加 `HD国语中字无水印`、`最新电影www.dyg7.com` 等自定义片段 → 保存 → 列表**立即刷新**（脏字段消失、分组更合理）。
- 连播到某组末集后，**自动续播下一组**首集。
- 关闭重开应用，配置仍生效（持久化）。

- [ ] **Step 5: 更新手测文档（可选）**

如仓库有 P2.5 风格的 smoke checklist，追加本次条目并提交。

```bash
git add -A
git commit -m "docs: smoke checklist for grouping + name cleaning"
```

---

## Self-Review

**Spec coverage：**
- F1 控制栏并入剧集列表按钮 → Task 7 ✓
- F2 NameCleaner / 配置模型 / 持久化 / 配置对话框 / 保存即刷新 → Task 1/2/3/6 + Task 5（reapply）✓
- 内置规则 + 自定义文字 → Task 1（模型）+ Task 2（引擎）+ Task 6（UI）✓
- F3 模型分组 / scanner 分组 / 无剧名回退父文件夹 / 跨组连播 / 分组侧边栏 → Task 4 + Task 8；跨组连播由 `Series.episodes` 扁平 getter + 现有 `PlaybackQueue` 自然实现（Task 4 注明）✓
- shared_preferences 依赖与平台注册 → Task 0 ✓

**Placeholder scan：** Task 5 Step 5 与 Task 8 Step 1 的测试用例以注释描述、依赖"沿用文件现有 fake 风格"——因这两处测试强依赖各自文件已有的注入脚手架，实施者需按现存模式补全断言；其余步骤均含完整可运行代码。实施时若发现现有脚手架不足，按相邻任务的 ProviderContainer / 临时目录模式落实。

**Type consistency：** `NameCleanConfig`(enabledBuiltinRules/customSnippets)、`NameCleaner.clean(fileName, parentDirName, config)`→`CleanedName(displayName, seriesTitle, season, episodeNumber)`、`Series(name, rootPath, groups)`/`SeriesGroup(title, episodes)`/`Episode(...displayName...)`、`LibraryScanner.scan(path,[config])`、`nameCleanConfigProvider`/`NameCleanConfigController.save`、`libraryActionsProvider`/`LibraryActions.reapplyCurrent` 在各引用任务间签名一致。
