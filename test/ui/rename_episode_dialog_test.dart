import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/ui/rename_episode_dialog.dart';

class _RecordingActions implements LibraryActions {
  String? renamedTo;
  @override
  Future<void> renameEpisode(Episode ep, String newBaseName) async {
    renamedTo = newBaseName;
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('预填真实文件主名（不含扩展名），确认后调用 renameEpisode', (tester) async {
    final actions = _RecordingActions();
    await tester.pumpWidget(ProviderScope(
      overrides: [libraryActionsProvider.overrideWithValue(actions)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showRenameEpisodeDialog(ctx,
                  Episode(path: '/d/逆天邪神01.2160p.mp4', fileName: '逆天邪神01.2160p.mp4')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 预填真实主名（去扩展名）
    expect(find.text('逆天邪神01.2160p'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '逆天邪神 01');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(actions.renamedTo, '逆天邪神 01');
  });
}
