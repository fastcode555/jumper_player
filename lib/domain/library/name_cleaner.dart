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
  // Pattern rules applied to content (not bracket groups themselves).
  static final Map<BuiltinNoiseRule, RegExp> _rulePatterns = {
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

  static final RegExp _separators = RegExp(r'[\s._]+');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static String _stem(String name) =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  /// Returns true if all runes in [s] are ASCII (< 128).
  static bool _isPureAscii(String s) => s.runes.every((r) => r < 128);

  /// Apply the new pipeline (steps 3a–3d) to [input].
  /// [forTitle] — if false we still strip episode tokens before bracket
  ///              processing (unused here; caller does that on cleanedStem).
  static String _applyPipeline(String input, NameCleanConfig config) {
    var s = input;

    // 3a. Custom snippets — literal substring delete, case-insensitive.
    for (final snippet in config.customSnippets) {
      if (snippet.isEmpty) continue;
      s = s.replaceAll(
          RegExp(RegExp.escape(snippet), caseSensitive: false), ' ');
    }

    // 3b. Pattern rules (resolution / codecSource / year) — replace matches
    //     inside the working string with spaces so bracket interiors become
    //     empty after the rule fires (e.g. `[2024]` → `[ ]`).
    for (final rule in [
      BuiltinNoiseRule.resolution,
      BuiltinNoiseRule.codecSource,
      BuiltinNoiseRule.year,
    ]) {
      if (config.enabledBuiltinRules.contains(rule)) {
        s = s.replaceAll(_rulePatterns[rule]!, ' ');
      }
    }

    // 3c. Bracket / paren group processing.
    final latinEnabled =
        config.enabledBuiltinRules.contains(BuiltinNoiseRule.latinBracketTags);

    // Process square brackets.
    s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]'), (m) {
      final inner = m.group(1)!.trim();
      if (inner.isEmpty) return ' ';
      if (latinEnabled && _isPureAscii(inner)) return ' ';
      return ' $inner ';
    });

    // Process round brackets.
    s = s.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
      final inner = m.group(1)!.trim();
      if (inner.isEmpty) return ' ';
      if (latinEnabled && _isPureAscii(inner)) return ' ';
      return ' $inner ';
    });

    // 3d. Normalize.
    return _normalize(s);
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
    final cleaned = _applyPipeline(_stem(dirName), config);
    return cleaned.isEmpty ? dirName : cleaned;
  }

  static CleanedName clean(
    String fileName,
    String parentDirName,
    NameCleanConfig config,
  ) {
    final parsed = EpisodeSorter.parse(fileName); // 基于原始文件名
    final stem = _stem(fileName);

    // Steps 3a-3d.
    final cleanedStem = _applyPipeline(stem, config);

    // Step 4: derive seriesTitle by stripping episode tokens from cleanedStem.
    var title = _stripEpisodeTokens(cleanedStem);
    if (title.isEmpty || _digitsOnly.hasMatch(title)) {
      title = cleanDir(parentDirName, config);
    }
    if (title.isEmpty) title = stem;

    // Step 5: displayName.
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
