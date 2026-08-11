// 轻量工作台 Flutter 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/core.dart';
import 'pages/home_page.dart';
import 'pages/news_page.dart';
import 'pages/ai_page.dart';
import 'pages/schedule_page.dart';
import 'pages/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init(); // 初始化本地存储（必须，否则待办/Key/记忆无法持久化）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const WorkbenchApp());
}

class WorkbenchApp extends StatelessWidget {
  const WorkbenchApp({super.key});

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
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2BB8C6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E0F13),
      ),
      themeMode: Store.darkMode ? ThemeMode.dark : ThemeMode.light,
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
            icon: Icon(Store.darkMode ? Icons.light_mode : Icons.dark_mode),
            tooltip: '切换主题',
            onPressed: () => setState(() => Store.darkMode = !Store.darkMode),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
