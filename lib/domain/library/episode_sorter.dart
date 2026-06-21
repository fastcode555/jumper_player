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
  // 方括号纯数字集号，如 [01]、[12]（1-3位）。
  static final RegExp _bracketNumber = RegExp(r'\[(\d{1,3})\]');
  // 噪声 token：方括号/圆括号组、分辨率、编码/来源、年份。
  static final RegExp _noiseTokens = RegExp(
    r'\[[^\]]*\]'                                             // [bracket groups]
    r'|\([^)]*\)'                                             // (paren groups)
    r'|\b\d{3,4}[pi]\b'                                       // e.g. 1080p 720i
    r'|\b(4k|2k|2160p|1080p|720p|480p)\b'                    // named resolutions
    r'|\b(x264|x265|h\.?264|h\.?265|hevc|avc|aac|flac'
    r'|web-?rip|web-?dl|webdl|bluray|bdrip|dts|ddp?5?\.?1)\b' // codecs/sources
    r'|\b(19|20)\d{2}\b',                                     // years
    caseSensitive: false,
  );
  static final RegExp _anyNumber = RegExp(r'\d{1,4}');

  static ParsedEpisode? parse(String fileName) {
    // 1. SxxExx（季+集）
    final m1 = _sxxExx.firstMatch(fileName);
    if (m1 != null) {
      return ParsedEpisode(int.parse(m1.group(1)!), int.parse(m1.group(2)!));
    }
    // 2. 中文 第N集/话/話/期
    final m2 = _cnWithPrefix.firstMatch(fileName);
    if (m2 != null) {
      return ParsedEpisode(null, int.parse(m2.group(1)!));
    }
    // 3. 中文 N集/话/話/期（无"第"）
    final m3 = _cnNoPrefix.firstMatch(fileName);
    if (m3 != null) {
      return ParsedEpisode(null, int.parse(m3.group(1)!));
    }
    // 4. EP\d+ / E\d+
    final m4 = _epPrefix.firstMatch(fileName);
    if (m4 != null) {
      return ParsedEpisode(null, int.parse(m4.group(1)!));
    }
    // 5. 方括号纯数字集号 [01] — 必须在清洗步骤之前，因清洗会删除方括号组。
    final m5 = _bracketNumber.firstMatch(fileName);
    if (m5 != null) {
      return ParsedEpisode(null, int.parse(m5.group(1)!));
    }
    // 6. 先去扩展名，再移除噪声 token，然后取末尾数字。
    final stem = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final cleaned = stem.replaceAll(_noiseTokens, ' ');
    final all = _anyNumber.allMatches(cleaned).toList();
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
