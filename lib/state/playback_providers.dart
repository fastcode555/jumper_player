import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';

final playerEngineProvider = Provider<PlayerEngine>((ref) {
  throw UnimplementedError(
    'playerEngineProvider must be overridden at app startup',
  );
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playerEngineProvider).playingStream;
});

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playerEngineProvider).positionStream;
});
