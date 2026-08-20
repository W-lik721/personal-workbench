// 个人工作台 Flutter 入口
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/core.dart';
import 'services/notifier.dart';
import 'services/sync.dart';
import 'boards.dart';
import 'nav_notifier.dart';

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
      title: '个人工作台',
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
        // 底部导航：选中态青色实色胶囊 + 白图标白字（点亮感），未选中低调灰
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          elevation: 3,
          indicatorColor: const Color(0xFF2BB8C6),
          labelTextStyle: WidgetStateProperty.resolveWith((s) {
            const base = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
            return s.contains(WidgetState.selected)
                ? base.copyWith(fontWeight: FontWeight.bold, color: Colors.white)
                : base.copyWith(color: Colors.black54);
          }),
          iconTheme: WidgetStateProperty.resolveWith((s) {
            return s.contains(WidgetState.selected)
                ? const IconThemeData(size: 24, color: Colors.white)
                : const IconThemeData(size: 22, color: Colors.black54);
          }),
        ),
        // 全局按钮统一圆角 12 + 舒适内边距，视觉更精致
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
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
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          elevation: 3,
          indicatorColor: const Color(0xFF2BB8C6),
          labelTextStyle: WidgetStateProperty.resolveWith((s) {
            const base = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
            return s.contains(WidgetState.selected)
                ? base.copyWith(fontWeight: FontWeight.bold, color: Colors.white)
                : base.copyWith(color: Colors.white70);
          }),
          iconTheme: WidgetStateProperty.resolveWith((s) {
            return s.contains(WidgetState.selected)
                ? const IconThemeData(size: 24, color: Colors.white)
                : const IconThemeData(size: 22, color: Colors.white70);
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
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
  late List<BoardMeta> _boards;

  @override
  void initState() {
    super.initState();
    _boards = buildBoards(Store.navConfig); // 按存储的导航配置动态生成 7 个板块
    aiAskGlobal = _askAi;
    switchTabGlobal = (i) => setState(() => _index = i.clamp(0, _boards.length - 1));
    navConfigNotifier.addListener(_rebuildBoards); // 设置页改了导航/删了板块→刷新
    if (!Store.onboarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOnboarding());
    }
    _autoBackup();
  }

  // 导航配置变化时重建底部导航（保持当前位置尽量有效）
  void _rebuildBoards() {
    if (!mounted) return;
    final b = buildBoards(Store.navConfig);
    setState(() {
      _boards = b;
      if (_index >= _boards.length) _index = _boards.length - 1;
    });
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

  // 主题模式中文标签（用于切换按钮 tooltip / 长按提示）
  String _themeModeLabel() {
    final m = themeModeNotifier.value;
    if (m == 'system') return '跟随系统';
    return m == 'dark' ? '深色' : '浅色';
  }

  String _themeModeLabelFull() {
    final eff = darkModeNotifier.value ? '当前显示深色' : '当前显示浅色';
    return '${_themeModeLabel()} · $eff';
  }

  // 首次启动轻引导：介绍各 Tab 用途，看完标记已引导（只弹一次）
  Future<void> _showOnboarding() async {
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('欢迎使用个人工作台'),
        content: const SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('一个把日常事务收拢到一处的工具：'),
            const SizedBox(height: 10),
            Text('· 首页：待办 / 番茄钟 / 速记 / 收藏'),
            Text('· 学习：倒计时 / GPA / 论文进度 / 闪卡'),
            Text('· AI：问问题、自动记住你的偏好'),
            Text('· 资讯：看新闻、收藏稍后读'),
            Text('· 工具：常用入口与自定义板块'),
            Text('· 课程表：导入你的课表'),
            Text('· 设置：主题、云备份、API Key'),
            const SizedBox(height: 10),
            Text('数据默认只存在本机，记得在「设置 → 云同步」开备份防丢。'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('跳过')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('开始使用')),
        ],
      ),
    );
    if (mounted) Store.onboarded = true; // 看过即标记，不再弹（无论点开始还是跳过）
  }

  @override
  void dispose() {
    aiAskGlobal = null;
    switchTabGlobal = null;
    navConfigNotifier.removeListener(_rebuildBoards);
    super.dispose();
  }

  void _askAi(String text, {String mode = '', bool send = false}) {
    aiFillGlobal?.call(text); // 把问题填进 AI 输入框
    final i = _boards.indexWhere((b) => b.id == 'ai'); // 动态顺序下找到 AI 页位置
    setState(() => _index = i < 0 ? _index : i);
    // mode/send 由 ai_page 的 aiAskGlobal 处理；main.dart 兜底只负责跳转。
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人工作台'),
        actions: [
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            tooltip: '切换主题（当前：${_themeModeLabel()}）',
            // 深/浅间翻转并固定模式（跟随系统时按当前亮度翻转；同时退出 system 模式）
            onPressed: () => themeModeNotifier.value = darkModeNotifier.value ? 'light' : 'dark',
            onLongPress: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('当前主题模式：${_themeModeLabelFull()}')),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _boards.map((b) => b.page).toList()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick(); // 轻触感：切换 Tab
          setState(() => _index = i);
        },
        destinations: _boards.map((b) => NavigationDestination(icon: b.icon, label: b.label)).toList(),
      ),
    );
  }
}
