// test/ui/name_clean_config_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/ui/name_clean_config_dialog.dart';

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
}
