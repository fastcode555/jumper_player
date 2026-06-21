import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/ui/player_page.dart';

void main() {
  testWidgets('shows Open File button initially', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerEngineProvider.overrideWithValue(FakePlayerEngine())],
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    expect(find.text('打开文件'), findsOneWidget);
  });
}
