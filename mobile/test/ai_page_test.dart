import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite_workbench/pages/ai_page.dart';
import 'package:lite_workbench/services/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  // 把 AI 页包进 Scaffold（生产里也如此，提供 DropdownButton 需要的 Material 祖先）
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AiPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('AI 页能正常构建（空状态提示 + 发送键 + 记忆键）', (WidgetTester tester) async {
    await pumpPage(tester);
    // 空状态提示语出现
    expect(find.textContaining('输入你的问题'), findsOneWidget);
    // 发送按钮（tooltip 含"发送"）
    expect(find.byWidgetPredicate((w) => w is IconButton && (w.tooltip?.contains('发送') ?? false)), findsOneWidget);
    // 记忆开关按钮（tooltip 含"AI 记忆"）
    expect(find.byWidgetPredicate((w) => w is IconButton && (w.tooltip?.contains('AI 记忆') ?? false)), findsOneWidget);
  });

  testWidgets('记忆开关：点击后 Store.aiMemoryOn 翻转，图标文案同步切换', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(Store.aiMemoryOn, true); // 默认开

    final memOn = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'AI 记忆已开（点此关闭）');
    expect(memOn, findsOneWidget);

    // 点一下 → 关
    await tester.tap(memOn);
    await tester.pumpAndSettle();
    expect(Store.aiMemoryOn, false);
    expect(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'AI 记忆已关（点此开启）'), findsOneWidget);

    // 再点一下 → 开
    final memOff = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'AI 记忆已关（点此开启）');
    await tester.tap(memOff);
    await tester.pumpAndSettle();
    expect(Store.aiMemoryOn, true);
  });

  testWidgets('输入框清空按钮：有字时出现，点击后清空并消失', (WidgetTester tester) async {
    await pumpPage(tester);

    final tf = find.byType(TextField);
    await tester.enterText(tf, '今天有什么值得看的新闻？');
    await tester.pumpAndSettle();

    // 有字 → 清空按钮（tooltip "清空"）出现
    final clear = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '清空');
    expect(clear, findsOneWidget);

    // 点击清空
    await tester.tap(clear);
    await tester.pumpAndSettle();

    // 清空后按钮消失
    expect(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '清空'), findsNothing);
  });

  testWidgets('TypingDots 渲染三个跳动圆点', (WidgetTester tester) async {
    // TypingDots 是无限循环动画，不能用 pumpAndSettle（会一直等动画结束而超时），单帧 pump 即可
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TypingDots(color: Colors.grey))));
    await tester.pump();
    final circles = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
    );
    expect(circles, findsNWidgets(3));
  });
}
