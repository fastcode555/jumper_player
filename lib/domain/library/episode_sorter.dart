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
    // Strip file extension before the trailing-number fallback so that
    // digits in the extension (e.g. "mp4") are not mistaken for episode numbers.
    final stem = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final all = _anyNumber.allMatches(stem).toList();
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
