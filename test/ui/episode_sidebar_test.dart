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
      groups: [SeriesGroup(title: name, episodes: eps, dirPath: '/$name')],
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

  testWidgets('每个剧集项有两行标题与 more 菜单（打开所在位置/重命名）', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    await container.read(playbackQueueProvider.notifier).loadSeries(
          singleGroupSeries([
            Episode(path: '/x/e1.mkv', fileName: 'e1.mkv',
                displayName: '很长很长的名字需要换行展示的剧集 01', episodeNumber: 1),
          ], name: 'X'),
        );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EpisodeSidebar())),
    ));
    await tester.pump();

    // 标题两行
    final title = tester.widget<Text>(find.text('很长很长的名字需要换行展示的剧集 01'));
    expect(title.maxLines, 2);

    // more 菜单
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('打开所在位置'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
  });

  testWidgets('分组渲染：组标题 + 干净显示名，点击播放对应全局索引', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final series = Series(
      name: 'lib',
      rootPath: '/lib',
      groups: [
        SeriesGroup(title: '逆天邪神 第2季', dirPath: '/lib/逆天邪神 第2季', episodes: [
          Episode(
              path: '/a/1',
              fileName: 'f1',
              displayName: '逆天邪神 第2季 01',
              episodeNumber: 1),
          Episode(
              path: '/a/2',
              fileName: 'f2',
              displayName: '逆天邪神 第2季 02',
              episodeNumber: 2),
        ]),
        SeriesGroup(title: '成何体统', dirPath: '/lib/成何体统', episodes: [
          Episode(
              path: '/b/1',
              fileName: 'g1',
              displayName: '成何体统 01',
              episodeNumber: 1),
        ]),
      ],
    );

    await container.read(playbackQueueProvider.notifier).loadSeries(series);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EpisodeSidebar())),
      ),
    );
    await tester.pump();

    // Group headers present
    expect(find.text('逆天邪神 第2季'), findsOneWidget);
    expect(find.text('成何体统'), findsOneWidget);

    // displayName shown (not raw fileName)
    expect(find.text('逆天邪神 第2季 01'), findsOneWidget);

    // With collapsible UX: group A is auto-expanded (current), group B is collapsed.
    // Expand group B first, then tap its episode.
    await tester.tap(find.text('成何体统'));
    await tester.pump();

    // Tapping second group's first item plays global index 2
    await tester.tap(find.text('成何体统 01'));
    await tester.pump();
    expect(container.read(playbackQueueProvider).currentIndex, 2);
    expect(fake.openedPath, '/b/1');
  });

  testWidgets('分组默认收起，正在播放的组自动展开', (tester) async {
    final fake = FakePlayerEngine();
    final container = ProviderContainer(
        overrides: [playerEngineProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    await container.read(playbackQueueProvider.notifier).loadSeries(Series(
            name: 'lib',
            rootPath: '/lib',
            groups: [
              SeriesGroup(title: 'A', dirPath: '/lib/A', episodes: [
                Episode(
                    path: '/lib/A/1',
                    fileName: '1',
                    displayName: 'A 01',
                    episodeNumber: 1)
              ]),
              SeriesGroup(title: 'B', dirPath: '/lib/B', episodes: [
                Episode(
                    path: '/lib/B/1',
                    fileName: '1',
                    displayName: 'B 01',
                    episodeNumber: 1)
              ]),
            ]));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EpisodeSidebar()))));
    await tester.pump();
    expect(find.text('A'), findsOneWidget); // header
    expect(find.text('B'), findsOneWidget); // header
    expect(find.text('A 01'), findsOneWidget); // A expanded (current)
    expect(find.text('B 01'), findsNothing); // B collapsed
    // tap B header -> expands
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(find.text('B 01'), findsOneWidget);
  });

  testWidgets('组菜单有 打开所在位置/重命名/删除；文件菜单含 删除', (tester) async {
    final container = ProviderContainer(
        overrides: [playerEngineProvider.overrideWithValue(FakePlayerEngine())]);
    addTearDown(container.dispose);
    await container.read(playbackQueueProvider.notifier).loadSeries(Series(
            name: 'lib',
            rootPath: '/lib',
            groups: [
              SeriesGroup(title: 'A', dirPath: '/lib/A', episodes: [
                Episode(
                    path: '/lib/A/1',
                    fileName: '1',
                    displayName: 'A 01',
                    episodeNumber: 1)
              ]),
            ]));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EpisodeSidebar()))));
    await tester.pump();
    // open folder menu (header trailing more)
    await tester.tap(find.byKey(const Key('folder-menu-/lib/A')));
    await tester.pumpAndSettle();
    expect(find.text('打开所在位置'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsWidgets);
    // dismiss menu then open episode menu
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsWidgets);
  });
}
