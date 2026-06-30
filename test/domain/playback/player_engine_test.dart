import 'package:flutter_test/flutter_test.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

void main() {
  group('FakePlayerEngine', () {
    test('open records the opened path', () async {
      final engine = FakePlayerEngine();
      await engine.open('/movies/ep01.mkv');
      expect(engine.openedPath, '/movies/ep01.mkv');
    });

    test('play and pause emit on playingStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <bool>[];
      final sub = engine.playingStream.listen(emitted.add);
      await engine.play();
      await engine.pause();
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [true, false]);
      await sub.cancel();
    });

    test('seek pushes position onto positionStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <Duration>[];
      final sub = engine.positionStream.listen(emitted.add);
      await engine.seek(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [const Duration(seconds: 42)]);
      await sub.cancel();
    });

    test('emitCompleted pushes onto completedStream', () async {
      final engine = FakePlayerEngine();
      final emitted = <bool>[];
      final sub = engine.completedStream.listen(emitted.add);
      engine.emitCompleted();
      await Future<void>.delayed(Duration.zero);
      expect(emitted, [true]);
      await sub.cancel();
    });

    test('FakePlayerEngine emitDuration pushes onto durationStream', () async {
      final e = FakePlayerEngine();
      addTearDown(e.dispose);
      final f = expectLater(e.durationStream, emits(const Duration(minutes: 24)));
      e.emitDuration(const Duration(minutes: 24));
      await f;
    });

    test('FakePlayerEngine records seekedTo', () async {
      final e = FakePlayerEngine();
      addTearDown(e.dispose);
      await e.seek(const Duration(seconds: 90));
      expect(e.seekedTo, const Duration(seconds: 90));
    });
  });
}
