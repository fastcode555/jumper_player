// test/ui/name_clean_config_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/state/library_actions.dart';
import 'package:jump_player/ui/name_clean_config_dialog.dart';

/// A fake that satisfies the libraryActionsProvider override.
/// We override only reapplyCurrent to throw; openFolder is a no-op.
class _FakeLibraryActions implements LibraryActions {
  @override
  Future<void> openFolder(String path) async {}

  @override
  Future<void> reapplyCurrent() async {
    throw Exception('folder unmounted');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('展示内置规则开关并能添加自定义片段后保存', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: NameCleanConfigDialog())),
    ));
    await tester.pumpAndSettle();

    // 每个内置规则一个开关
    expect(find.byType(SwitchListTile), findsNWidgets(BuiltinNoiseRule.values.length));

    // 添加一个自定义片段
    await tester.enterText(find.byKey(const Key('snippet-input')), 'HD国语中字无水印');
    await tester.tap(find.byKey(const Key('snippet-add')));
    await tester.pump();
    expect(find.text('HD国语中字无水印'), findsOneWidget);

    // 保存
    await tester.tap(find.byKey(const Key('config-save')));
    await tester.pumpAndSettle();
  });

  testWidgets('reapplyCurrent 出错时显示 SnackBar 并关闭对话框', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final throwing = _FakeLibraryActions();

    // Open the dialog via showNameCleanConfigDialog so there is a real route
    // to pop, and the SnackBar lands on the parent Scaffold's messenger.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryActionsProvider.overrideWithValue(throwing),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              key: const Key('open-dialog'),
              onPressed: () => showNameCleanConfigDialog(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Open the dialog.
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();

    // Dialog should be visible.
    expect(find.byType(NameCleanConfigDialog), findsOneWidget);

    // Tap save — reapplyCurrent will throw.
    await tester.tap(find.byKey(const Key('config-save')));
    await tester.pumpAndSettle();

    // A SnackBar with error message should appear.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('无法重新生成命名'), findsOneWidget);
  });
}
