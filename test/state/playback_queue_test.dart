import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';

Series singleGroupSeries(List<Episode> eps, {String name = 's'}) => Series(
      name: name,
      rootPath: '/$name',
      groups: [SeriesGroup(title: name, episodes: eps)],
    );

Series _series() => singleGroupSeries([
      Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
      Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
      Episode(path: '/x/e3.mkv', fileName: 'e3.mkv', episodeNumber: 3),
    ], name: 'X');

void main() {
  late FakePlayerEngine fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakePlayerEngine();
    container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
  });
  tearDown(() => container.dispose());

  test('loadSeries plays the start episode', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    expect(fake.openedPath, '/x/e1.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 0);
  });

  test('next and previous walk the list', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    await c.next();
    expect(fake.openedPath, '/x/e2.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 1);
    await c.previous();
    expect(fake.openedPath, '/x/e1.mkv');
  });

  test('next at last episode is a no-op', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series(), startAt: 2);
    await c.next();
    expect(container.read(playbackQueueProvider).currentIndex, 2);
  });

  test('auto-advances on completion when not last', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    fake.emitCompleted();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(playbackQueueProvider).currentIndex, 1);
    expect(fake.openedPath, '/x/e2.mkv');
  });

  test('completion=false does not advance', () async {
    final c = container.read(playbackQueueProvider.notifier);
    await c.loadSeries(_series());
    fake.emitCompleted(false);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(playbackQueueProvider).currentIndex, 0);
  });
}
