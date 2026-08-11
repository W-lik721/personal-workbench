import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite_workbench/main.dart' as app;
import 'package:lite_workbench/services/core.dart';

void main() {
  testWidgets('顶部按钮切换深色模式即时生效（无需重启）', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    app.darkModeNotifier.value = Store.darkMode;

    await tester.pumpWidget(const app.WorkbenchApp());
    await tester.pumpAndSettle();

    // 从 MaterialApp 内部的 Scaffold 读"有效"主题亮度（在 Theme 包裹内才反映 themeMode）
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    final before = brightness();

    // 点 AppBar 的"切换主题"按钮
    await tester.tap(find.byTooltip('切换主题'));
    await tester.pumpAndSettle();

    final after = brightness();
    expect(after, isNot(equals(before)),
        reason: '切换主题后亮度应立刻翻转，不需要重启 App');
  });
}
