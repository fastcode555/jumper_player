// lib/infra/fs/file_system_ops.dart
import 'dart:io';

typedef ProcessRunner = Future<void> Function(
    String executable, List<String> args);

({String executable, List<String> args}) revealCommand(String path,
    {required String os}) {
  switch (os) {
    case 'windows':
      return (executable: 'explorer', args: ['/select,$path']);
    case 'linux':
      final dir = _parentDir(path);
      return (executable: 'xdg-open', args: [dir]);
    case 'macos':
    default:
      return (executable: 'open', args: ['-R', path]);
  }
}

abstract class FileSystemOps {
  Future<void> reveal(String path);

  /// Renames the file at [path] to [newBaseName] + original extension, in the
  /// same directory. Returns the new path. Throws [ArgumentError] for an empty
  /// or separator-containing name, and [FileSystemException] on collision.
  Future<String> rename(String path, String newBaseName);
}

class DefaultFileSystemOps implements FileSystemOps {
  DefaultFileSystemOps({ProcessRunner? runner, String? osOverride})
      : _run = runner ?? _defaultRun,
        _os = osOverride ?? _currentOs();

  final ProcessRunner _run;
  final String _os;

  static Future<void> _defaultRun(String e, List<String> a) async {
    await Process.run(e, a);
  }

  static String _currentOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'macos';
  }

  @override
  Future<void> reveal(String path) async {
    final c = revealCommand(path, os: _os);
    await _run(c.executable, c.args);
  }

  @override
  Future<String> rename(String path, String newBaseName) async {
    final base = newBaseName.trim();
    if (base.isEmpty || base.contains('/') || base.contains(r'\')) {
      throw ArgumentError('Invalid file name: "$newBaseName"');
    }
    final dir = _parentDir(path);
    final ext = _extension(path);
    final newPath = '$dir/$base$ext';
    if (newPath != path && File(newPath).existsSync()) {
      throw FileSystemException('Target already exists', newPath);
    }
    await File(path).rename(newPath);
    return newPath;
  }
}

String _parentDir(String path) {
  final norm = path.endsWith('/') || path.endsWith('\\')
      ? path.substring(0, path.length - 1)
      : path;
  final i = norm.lastIndexOf('/') > norm.lastIndexOf('\\')
      ? norm.lastIndexOf('/')
      : norm.lastIndexOf('\\');
  return i >= 0 ? norm.substring(0, i) : norm;
}

String _extension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i) : '';
}
