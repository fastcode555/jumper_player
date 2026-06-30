import 'dart:async';

abstract class PlayerEngine {
  Future<void> open(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<Duration> get durationStream;
  Future<void> dispose();
}

class FakePlayerEngine implements PlayerEngine {
  String? openedPath;
  int openCount = 0;
  Duration? seekedTo;
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _duration = StreamController<Duration>.broadcast();

  @override
  Future<void> open(String filePath) async {
    openedPath = filePath;
    openCount++;
  }

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> pause() async => _playing.add(false);

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    _position.add(position);
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  void emitCompleted([bool value = true]) => _completed.add(value);

  void emitDuration(Duration d) => _duration.add(d);

  void emitPosition(Duration p) => _position.add(p);

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
    await _completed.close();
    await _duration.close();
  }
}
