// 轻量工作台 Flutter 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/core.dart';
import 'services/notifier.dart';
import 'services/sync.dart';
import 'pages/home_page.dart';
import 'pages/news_page.dart';
import 'pages/ai_page.dart';
import 'pages/schedule_page.dart';
import 'pages/settings_page.dart';

// 主题切换通知器：让深处的开关能即时重建 MaterialApp（否则要重启才生效）
// darkModeNotifier = 实际亮度（深=真）；themeModeNotifier = 三态 'system'/'dark'/'light'
final darkModeNotifier = ValueNotifier<bool>(true);
final themeModeNotifier = ValueNotifier<String>('dark');

// 由三态模式解析实际亮度（system 时跟随系统亮度）
bool _resolveDark(String mode) {
  if (mode == 'dark') return true;
  if (mode == 'light') return false;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init(); // 初始化本地存储（必须，否则待办/Key/记忆无法持久化）
  await Store.clearHotCache(); // 清掉旧版技术热榜缓存（升级后避免一帧闪空卡）
  await Notifier.init(); // 初始化本地通知（待办提醒用；顺带申请 Android 13+ 通知权限）
  themeModeNotifier.value = Store.themeMode;
  darkModeNotifier.value = _resolveDark(Store.themeMode); // 以已持久化的偏好初始化
  runApp(const WorkbenchApp());
}

class WorkbenchApp extends StatefulWidget {
  const WorkbenchApp({super.key});

  @override
  State<WorkbenchApp> createState() => _WorkbenchAppState();
}

class _WorkbenchAppState extends State<WorkbenchApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUi(); // 状态栏图标颜色跟随初始主题
    darkModeNotifier.addListener(_onDarkChanged);
    themeModeNotifier.addListener(_onThemeModeChanged);
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

  // 三态切换：持久化 + 重算实际亮度
  void _onThemeModeChanged() {
    Store.themeMode = themeModeNotifier.value;
    darkModeNotifier.value = _resolveDark(themeModeNotifier.value);
    setState(() {});
  }

  // 系统亮度变化（仅"跟随系统"模式生效）
  @override
  void didChangePlatformBrightness() {
    if (themeModeNotifier.value == 'system') {
      darkModeNotifier.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    darkModeNotifier.removeListener(_onDarkChanged);
    themeModeNotifier.removeListener(_onThemeModeChanged);
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
      themeMode: themeModeNotifier.value == 'system'
          ? ThemeMode.system
          : (themeModeNotifier.value == 'dark' ? ThemeMode.dark : ThemeMode.light),
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
    _autoBackup();
  }

  // 启动时自动云备份（设置里开了且已配 Token 才生效；静默失败不打扰）
  Future<void> _autoBackup() async {
    if (!Store.autoSync) return;
    final token = await Store.syncToken();
    if (token.isEmpty) return;
    try {
      await Sync.upload(token, Store.syncRepo);
    } catch (_) {}
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
            // 深/浅间翻转并固定模式（跟随系统时按当前亮度翻转；同时退出 system 模式）
            onPressed: () => themeModeNotifier.value = darkModeNotifier.value ? 'light' : 'dark',
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
