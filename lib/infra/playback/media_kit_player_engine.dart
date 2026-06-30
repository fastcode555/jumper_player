import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine() : _player = Player();

  final Player _player;

  Player get raw => _player;

  late final VideoController videoController = VideoController(_player);

  @override
  Future<void> open(String filePath) =>
      _player.open(Media(filePath), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Future<void> dispose() => _player.dispose();
}
