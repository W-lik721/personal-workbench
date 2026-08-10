// 轻量工作台 Flutter 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/core.dart';
import 'pages/home_page.dart';
import 'pages/news_page.dart';
import 'pages/ai_page.dart';
import 'pages/schedule_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final _pages = [const HomePage(), const NewsPage(), const AiPage(), const SchedulePage()];

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
    setState(() => _index = 2); // 切到 AI tab
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切到 AI 助手，问题已复制：${text.length > 30 ? text.substring(0, 30) + '…' : text}')));
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
        ],
      ),
    );
  }
}
