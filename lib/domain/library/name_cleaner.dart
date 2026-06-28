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
