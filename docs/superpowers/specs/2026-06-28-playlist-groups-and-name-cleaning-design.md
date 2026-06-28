# 播放列表分组 + 文件名清洗映射 — 设计文档

日期：2026-06-28
状态：已确认，待转实现计划

## 背景与目标

当前播放器把所选文件夹**递归扁平化**成单一的剧集列表，存在两个问题：

1. 控制不统一：剧集列表开关是一个浮动在画面左上角的按钮，与底部控制栏割裂。
2. 文件名嘈杂：下载来的文件名含大量无意义片段（如 `[GM-Team]`、`[国漫]`、`2160p`、
   `HD国语中字无水印`、`[最新电影www.dyg7.com]`），且一个文件夹里常混有多部剧，扁平列表
   既难读也分不清归属。

本次三项改动：

- **F1**：把"剧集列表"开关按钮并入底部控制栏。
- **F2**：在加载时为每个文件生成**干净的显示名（映射名）**，不修改磁盘文件/文件夹名；噪声规则
  可配置并持久化。
- **F3**：播放列表由扁平列表改为**按识别出的剧名分组**。

**非目标**：不做磁盘文件改名（明确非破坏性）；不做正则自定义（仅内置规则开关 + 自定义文字片段）。

## 关键决策（已与用户确认）

- 干净名仅用于**显示**，不触碰磁盘文件名/文件夹名。
- 噪声匹配 = **内置智能规则（可开关）+ 用户自定义文字片段**。
- 持久化使用 **shared_preferences**（新增依赖；项目当前无任何本地存储库）。
- 分组依据 = **从干净名识别出的剧名**（即使多部剧混在同一扁平文件夹也能拆开）；
  **识别不出剧名时（去噪后为空或纯数字）回退到父文件夹名（经同样清洗）**。
- 跨组连播：自动连播到组末尾后**继续播放下一组**。
- **只新增一个"配置"按钮**；配置保存即自动重新生成显示名与分组（无独立"重命名"按钮）。
- 加载（导入）时即按已保存规则自动生成映射名；之后改配置保存即刷新。

## 架构总览

分层沿用现有结构（domain / state / ui）：

```
domain/library/
  name_cleaner.dart        ← 新增：原始文件名 + 规则 → 干净显示名 + 剧名 + 集号
  name_clean_config.dart   ← 新增：内置规则枚举 + 配置模型(纯数据，可序列化)
  episode_sorter.dart      ← 复用其噪声正则；按规则拆成可独立开关的组
  library_models.dart      ← Episode 增加 displayName；新增 SeriesGroup；Series 持有 groups
  library_scanner.dart     ← 产出分组结构，扫描时套用 NameCleaner

infra/config/
  preferences_config_store.dart ← 新增：shared_preferences 读写 NameCleanConfig(JSON)

state/
  name_clean_providers.dart ← 新增：配置 provider（读写 + 通知）
  library_actions.dart      ← openFolder 时注入当前配置；保存配置后重扫/重映射当前库
  playback_queue.dart       ← 队列在「扁平全局顺序」上运行，但保留组边界用于显示
  ui_providers.dart         ← 维持 sidebarVisibleProvider

ui/
  control_bar.dart          ← 并入「剧集列表」开关 + 新增「配置」按钮
  episode_sidebar.dart      ← 改为分组展示（组标题 + 组内剧集）
  name_clean_config_dialog.dart ← 新增：配置对话框
  player_page.dart          ← 移除浮动按钮
```

## F1：剧集列表按钮并入控制栏

- 删除 `player_page.dart` 中 `Positioned(top:8,left:8)` 的浮动 `IconButton`。
- 在 `ControlBar` 中新增一枚 `IconButton`：icon `Icons.playlist_play`，tooltip `剧集列表`，
  onPressed 切换 `sidebarVisibleProvider`。
- 控制栏最终按钮顺序：
  `打开文件 · 打开文件夹 · 剧集列表 · ⏮ · ⏯ · ⏭ · 配置 · 全屏`。

## F2：干净显示名 + 噪声配置

### 数据模型

`NameCleanConfig`（纯数据，可 JSON 序列化）：

```
enabledBuiltinRules: Set<BuiltinNoiseRule>   // 默认全开
customSnippets: List<String>                 // 用户自定义精确子串
```

`BuiltinNoiseRule` 枚举（每项对应 EpisodeSorter `_noiseTokens` 中的一段正则）：

- `bracketGroups`   — `[...]` 方括号组
- `parenGroups`     — `(...)` 圆括号组
- `resolution`      — `\d{3,4}[pi]` 与命名分辨率（4k/2k/2160p/1080p/720p/480p）
- `codecSource`     — x264/x265/h264/h265/hevc/avc/aac/flac/web-rip/web-dl/bluray/bdrip/dts/ddp5.1
- `year`            — `(19|20)\d{2}`

### NameCleaner（domain，纯函数，无 IO）

输入：`rawFileName`、`parentDirName`、`NameCleanConfig`。
输出：`CleanedName { displayName, seriesTitle, episodeNumber, season }`。

步骤：

1. **先解析集号/季**：调用 `EpisodeSorter.parse(rawFileName)` 取 `season/episode`（其内部逻辑
   不变，确保集号识别在清洗之前完成——注意方括号纯数字集号 `[01]` 必须在删括号组之前提取）。
2. **去扩展名**得到 stem。
3. **删内置规则命中片段**：按 `enabledBuiltinRules` 选择性应用对应正则替换为空格。
4. **删自定义片段**：对 `customSnippets` 逐条做字面子串删除（大小写不敏感）。
5. **归一化**：折叠多余空白与残留分隔符（`._-` 连续段 → 单空格）、trim。
6. **得 seriesTitle**：在 4/5 之后，从结果中移除集号 token（`SxxEyy`、`第N集/话/話/期`、
   `EP12`、`[01]` 方括号纯数字集号）得到剧名。**注意不要盲删所有裸数字**（会破坏中文标题里
   的 `第2季` 等），只删上述明确的集号 token。
7. **seriesTitle 兜底**：若第 6 步结果为空、或归一化后只剩纯数字（如 `01`），则
   `seriesTitle = NameCleaner.clean(parentDirName, config).displayName`（即对父文件夹名套用
   同一套清洗，取其结果；为避免递归，对目录名只走 2–5 步清洗，不取集号）。
8. **displayName**：有集号时 = `seriesTitle 规范化集号`（集号补零两位，如 `逆天邪神 第2季 01`）；
   无集号时 = 清洗后的 stem（若为空再回退原始去扩展名 stem）。

> 边界：清洗只影响显示名与分组键；集号解析始终基于**原始**文件名，避免清洗误删集号。

### 持久化

`infra/config/PreferencesConfigStore`：用 `shared_preferences` 把 `NameCleanConfig` 存成一个
JSON 字符串键（如 `name_clean_config_v1`）。读：无值时返回默认（全部内置规则开、无自定义片段）。

### 配置对话框（ui）

`NameCleanConfigDialog`：

- **内置规则**：每条规则一个 `SwitchListTile`。
- **自定义片段**：输入框 + 添加按钮；下方列表每项带删除按钮。
- **从当前文件名检测**：可选辅助——扫描当前已加载库的原始文件名，提取高频候选噪声（如反复出现
   的方括号组/网址样片段）供一键加入自定义片段。
- **保存**：写入持久化 → 触发当前库重新生成显示名 + 重新分组（见 F3）。**保存即生效**，
  无独立"重命名"按钮。
- 取消：不改动。

### 控制栏「配置」按钮

icon `Icons.tune`（或 `Icons.settings`），tooltip `命名配置`，onPressed 打开
`NameCleanConfigDialog`。

## F3：播放列表分组

### 数据模型

```
Episode { path, fileName, displayName, season?, episodeNumber? }   // 增 displayName
SeriesGroup { title, episodes: List<Episode> }                     // 新增
Series { rootPath, groups: List<SeriesGroup> }                     // episodes → groups
```

### 扫描与分组（LibraryScanner）

1. 递归扫描视频文件（保持现有扩展名集合与跨平台 baseName 逻辑）。
2. 对每个文件用 `NameCleaner`（注入当前配置 + 该文件父文件夹名）得到
   `displayName / seriesTitle / 集号`；seriesTitle 为空/纯数字时已在 NameCleaner 内回退父文件夹名。
3. 以 `seriesTitle` 为键归组；组间用 `EpisodeSorter.compareNatural` 按标题自然排序；
   组内用现有 `EpisodeSorter.sort` 规则按集号排序。
4. 产出 `Series { rootPath, groups }`。

### 播放队列（PlaybackQueue）

- **全局顺序** = 各组按序拼接后的扁平 `episodes`（组1 第1..n → 组2 第1..n …）。
- 队列在该全局顺序上运行，`上一集/下一集/自动连播`沿全局顺序无缝推进，**跨组自动续播**。
- 额外维护「全局索引 → (组下标, 组内下标)」映射，供侧边栏定位高亮与点击播放。
- `loadSeries` 接收新的 `Series{groups}`；扁平展开后逻辑与现状基本一致（最小改动）。

### 侧边栏（EpisodeSidebar）

- 改为分组展示：每组一个标题头（剧名），其下为该组剧集列表；当前播放项高亮（amber）。
- 标题显示 `episode.displayName`（干净名），不再显示原始 `fileName`。
- 点击任一剧集 → 通过映射换算成全局索引并 `playAt`。
- 组的折叠/展开：默认展开当前播放所在组；其余可折叠（用 `ExpansionTile` 或自绘 header）。

## 错误处理

- 文件夹扫描失败：维持现有 SnackBar 提示（`无法扫描该文件夹`）。
- 配置 JSON 解析失败：回退默认配置，不崩溃。
- 清洗结果为空：回退原始文件名（去扩展名），保证列表始终有可读文本。
- 识别不出集号：该文件归入其 seriesTitle 组，排序回退到 `compareNatural`（沿用现有逻辑）。

## 测试策略（TDD）

domain 层为主，纯函数易测：

- `name_cleaner_test`：各内置规则单独/组合、自定义片段、集号保护、空兜底、中英文混合样例
  （用用户真实样例：`[GM-Team][国漫][逆天邪神 第2季][...][01][2160p].mp4`、
  `01.2160p.HD国语中字无水印[最新电影www.dyg7.com].mp4`）。
- `name_clean_config_test`：序列化/反序列化、默认值、未知字段容错。
- `library_scanner_test`：分组正确性（多剧混放拆分）、组内/组间排序。
- `preferences_config_store_test`：用 `SharedPreferences.setMockInitialValues` 读写往返。
- `playback_queue_test`：跨组 next/previous/auto-next、全局↔分组索引映射、组边界续播。
- `episode_sidebar_test` / `control_bar_test` / `player_page_test`：按钮迁移、配置按钮存在、
  分组渲染与点击播放、显示干净名。

## 依赖变更

- 新增 `shared_preferences`（pubspec + 各桌面平台 GeneratedPluginRegistrant + Podfile.lock）。

## 影响面 / 兼容

- `Series.episodes` → `Series.groups` 是破坏性模型变更，涉及 scanner、queue、sidebar、相关测试，
  需一并更新。
- 控制栏新增/迁移按钮，更新对应 widget 测试。
```
