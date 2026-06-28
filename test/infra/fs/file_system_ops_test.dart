// test/infra/fs/file_system_ops_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/infra/fs/file_system_ops.dart';

void main() {
  group('revealCommand', () {
    test('macOS uses open -R', () {
      final c = revealCommand('/a/b.mp4', os: 'macos');
      expect(c.executable, 'open');
      expect(c.args, ['-R', '/a/b.mp4']);
    });
    test('windows uses explorer /select', () {
      final c = revealCommand(r'C:\a\b.mp4', os: 'windows');
      expect(c.executable, 'explorer');
      expect(c.args, [r'/select,C:\a\b.mp4']);
    });
    test('linux opens parent dir', () {
      final c = revealCommand('/a/b.mp4', os: 'linux');
      expect(c.executable, 'xdg-open');
      expect(c.args, ['/a']);
    });
  });

  group('reveal', () {
    test('runs the platform command', () async {
      String? exe;
      List<String>? args;
      final ops = DefaultFileSystemOps(
        osOverride: 'macos',
        runner: (e, a) async {
          exe = e;
          args = a;
        },
      );
      await ops.reveal('/x/y.mp4');
      expect(exe, 'open');
      expect(args, ['-R', '/x/y.mp4']);
    });
  });

  group('rename', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('fsops_'));
    tearDown(() => tmp.existsSync() ? tmp.deleteSync(recursive: true) : null);

    test('keeps extension, returns new path', () async {
      final f = File('${tmp.path}/old.mp4')..writeAsStringSync('x');
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      final newPath = await ops.rename(f.path, '逆天邪神01');
      expect(newPath, '${tmp.path}/逆天邪神01.mp4');
      expect(File(newPath).existsSync(), isTrue);
      expect(f.existsSync(), isFalse);
    });

    test('throws on empty / separator / collision', () async {
      final f = File('${tmp.path}/a.mp4')..writeAsStringSync('x');
      File('${tmp.path}/taken.mp4').writeAsStringSync('y');
      final ops = DefaultFileSystemOps(runner: (_, __) async {});
      expect(() => ops.rename(f.path, '  '), throwsArgumentError);
      expect(() => ops.rename(f.path, 'a/b'), throwsArgumentError);
      expect(() => ops.rename(f.path, 'taken'), throwsA(isA<FileSystemException>()));
    });
  });
}
