import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/domain/window/window_controller.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/window_providers.dart';
import 'package:jump_player/ui/control_bar.dart';
import 'package:jump_player/ui/player_page.dart';

void main() {
  testWidgets('renders ControlBar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerEngineProvider.overrideWithValue(FakePlayerEngine()),
          windowControllerProvider.overrideWithValue(FakeWindowController()),
        ],
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    expect(find.byType(ControlBar), findsOneWidget);
  });
}
