import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/library_actions.dart';

void main() {
  test('openFolder scans and loads first episode into the queue', () async {
    final tmp = Directory.systemTemp.createTempSync('lib_actions_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/第1集.mp4').writeAsStringSync('x');
    File('${tmp.path}/第2集.mp4').writeAsStringSync('x');

    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(libraryActionsProvider).openFolder(tmp.path);

    final state = container.read(playbackQueueProvider);
    expect(state.episodes.length, 2);
    expect(state.currentIndex, 0);
    expect(fake.openedPath, endsWith('第1集.mp4'));
  });
}
