import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

void main() {
  test('isPlayingProvider reflects engine play()', () async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final sub = container.listen(isPlayingProvider, (_, __) {});
    await fake.play();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(isPlayingProvider).value, true);
    sub.close();
  });
}
