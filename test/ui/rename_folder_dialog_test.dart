import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/ui/rename_folder_dialog.dart';

class _RecordingActions implements LibraryActions {
  String? renamedFolderTo;
  @override
  Future<void> renameFolder(SeriesGroup group, String newName) async {
    renamedFolderTo = newName;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('预填目录名（dirPath 的 basename），确认后调用 renameFolder', (tester) async {
    final actions = _RecordingActions();
    final group = SeriesGroup(
        title: '逆天邪神 第2季',
        dirPath: '/lib/逆天邪神 第2季',
        episodes: []);
    await tester.pumpWidget(ProviderScope(
      overrides: [libraryActionsProvider.overrideWithValue(actions)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showRenameFolderDialog(ctx, group),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // prefilled with basename of dirPath
    expect(find.text('逆天邪神 第2季'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '逆天邪神 第2季 修改版');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(actions.renamedFolderTo, '逆天邪神 第2季 修改版');
  });
}
