// 轻量工作台 Flutter 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/core.dart';
import 'services/notifier.dart';
import 'pages/home_page.dart';
import 'pages/news_page.dart';
import 'pages/ai_page.dart';
import 'pages/schedule_page.dart';
import 'pages/settings_page.dart';

// 主题切换通知器：让深处的开关能即时重建 MaterialApp（否则要重启才生效）
final darkModeNotifier = ValueNotifier<bool>(true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init(); // 初始化本地存储（必须，否则待办/Key/记忆无法持久化）
  await Store.clearHotCache(); // 清掉旧版技术热榜缓存（升级后避免一帧闪空卡）
  await Notifier.init(); // 初始化本地通知（待办提醒用；顺带申请 Android 13+ 通知权限）
  darkModeNotifier.value = Store.darkMode; // 以已持久化的偏好初始化
  runApp(const WorkbenchApp());
}

class WorkbenchApp extends StatefulWidget {
  const WorkbenchApp({super.key});

  @override
  State<WorkbenchApp> createState() => _WorkbenchAppState();
}

class _WorkbenchAppState extends State<WorkbenchApp> {
  @override
  void initState() {
    super.initState();
    _applySystemUi(); // 状态栏图标颜色跟随初始主题
    darkModeNotifier.addListener(_onDarkChanged);
  }

  // 状态栏/导航栏图标颜色随主题自适应（深色→浅色图标，浅色→深色图标），避免看不清
  void _applySystemUi() {
    final dark = darkModeNotifier.value;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
  }

  // 切换时：先持久化，再重建 MaterialApp 让主题立即生效，并同步状态栏图标
  void _onDarkChanged() {
    Store.darkMode = darkModeNotifier.value;
    _applySystemUi();
    setState(() {});
  }

  @override
  void dispose() {
    darkModeNotifier.removeListener(_onDarkChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻量工作台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2BB8C6),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // 全局卡片体系统一：扁平 0 阴影、圆角 14、页边距 12/6（实例级 margin 优先覆盖）
        cardTheme: CardThemeData(
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2BB8C6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E0F13),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
        ),
      ),
      themeMode: darkModeNotifier.value ? ThemeMode.dark : ThemeMode.light,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _pages = [
    const HomePage(),
    const NewsPage(),
    const AiPage(),
    const SchedulePage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    aiAskGlobal = _askAi;
  }

  @override
  void dispose() {
    aiAskGlobal = null;
    super.dispose();
  }

  void _askAi(String text) {
    aiFillGlobal?.call(text); // 把问题填进 AI 输入框
    setState(() => _index = 2); // 切到 AI tab
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛠️ 轻量工作台'),
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            tooltip: '切换主题',
            onPressed: () => darkModeNotifier.value = !darkModeNotifier.value,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick(); // 轻触感：切换 Tab
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), selectedIcon: Icon(Icons.newspaper), label: '日报'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI 助手'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '课程表'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
