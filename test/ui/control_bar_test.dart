import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/domain/window/window_controller.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_settings.dart';
import 'package:jump_player/state/window_providers.dart';
import 'package:jump_player/ui/control_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows tooltipped controls and toggles fullscreen', (tester) async {
    final fakeWin = FakeWindowController();
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      windowControllerProvider.overrideWithValue(fakeWin),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ControlBar())),
      ),
    );

    expect(find.byTooltip('打开文件'), findsOneWidget);
    expect(find.byTooltip('打开文件夹'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);

    await tester.tap(find.byTooltip('全屏'));
    await tester.pump();
    expect(container.read(isFullScreenProvider), isTrue);
    expect(fakeWin.fullScreen, isTrue);
  });

  testWidgets('控制栏含剧集列表与命名配置按钮', (tester) async {
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      windowControllerProvider.overrideWithValue(FakeWindowController()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ControlBar())),
      ),
    );

    expect(find.byTooltip('剧集列表'), findsOneWidget);
    expect(find.byTooltip('命名配置'), findsOneWidget);
  });

  testWidgets('控制栏有自动连播开关且可切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      playerEngineProvider.overrideWithValue(FakePlayerEngine()),
      windowControllerProvider.overrideWithValue(FakeWindowController()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ControlBar())),
    ));
    await tester.pump();

    expect(find.byTooltip('自动连播：开'), findsOneWidget);
    await tester.tap(find.byTooltip('自动连播：开'));
    await tester.pump();
    expect(container.read(autoAdvanceProvider), isFalse);
    expect(find.byTooltip('自动连播：关'), findsOneWidget);
  });
}
