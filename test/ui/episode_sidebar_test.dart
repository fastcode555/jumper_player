import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/ui/episode_sidebar.dart';

Series singleGroupSeries(List<Episode> eps, {String name = 's'}) => Series(
      name: name,
      rootPath: '/$name',
      groups: [SeriesGroup(title: name, episodes: eps)],
    );

void main() {
  testWidgets('lists episodes and highlights current; tap jumps', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(playbackQueueProvider.notifier).loadSeries(
          singleGroupSeries([
            Episode(path: '/x/e1.mkv', fileName: 'e1.mkv', episodeNumber: 1),
            Episode(path: '/x/e2.mkv', fileName: 'e2.mkv', episodeNumber: 2),
          ], name: 'X'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EpisodeSidebar())),
      ),
    );
    await tester.pump();

    expect(find.text('e1.mkv'), findsOneWidget);
    expect(find.text('e2.mkv'), findsOneWidget);

    await tester.tap(find.text('e2.mkv'));
    await tester.pump();
    expect(fake.openedPath, '/x/e2.mkv');
    expect(container.read(playbackQueueProvider).currentIndex, 1);
  });
}
