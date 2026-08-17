// 板块解析与注册：把"板块 ID"映射到 标题 / 图标 / 页面。
// 内置 7 个直接用现有页面；自定义板块（cb_xxx）统一指向 CustomBoardPage。
// 放在单独文件，避免 core.dart（纯 Dart，无 UI 依赖）引入 Flutter 控件。
import 'package:flutter/material.dart';
import 'lucide_nav_icons.dart';
import 'services/core.dart';
import 'pages/home_page.dart';
import 'pages/news_page.dart';
import 'pages/ai_page.dart';
import 'pages/schedule_page.dart';
import 'pages/study_page.dart';
import 'pages/tools_page.dart';
import 'pages/settings_page.dart';
import 'pages/custom_board_page.dart';

// 内置板块 ID（顺序即默认导航顺序）
const List<String> kBuiltInIds = ['home', 'news', 'ai', 'schedule', 'study', 'tools', 'settings'];

// 板块元信息：渲染底部导航与页面用
class BoardMeta {
  final String id;
  final String label;
  final Widget icon;
  final Widget page;
  const BoardMeta({required this.id, required this.label, required this.icon, required this.page});
}

// 自定义板块图标名 → Material 图标
IconData customIcon(String name) {
  switch (name) {
    case 'bookmark':
      return Icons.bookmark_rounded;
    case 'link':
      return Icons.link_rounded;
    case 'note':
      return Icons.note_rounded;
    case 'work':
      return Icons.work_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    case 'shopping':
      return Icons.shopping_bag_rounded;
    case 'music':
      return Icons.music_note_rounded;
    case 'game':
      return Icons.sports_esports_rounded;
    case 'home':
      return Icons.house_rounded;
    case 'star':
    default:
      return Icons.star_rounded;
  }
}

// 可选的自定义板块图标清单（新建/编辑板块时给用户的下拉）
const Map<String, String> customIconOptions = {
  'star': '星标',
  'bookmark': '书签',
  'link': '链接',
  'note': '笔记',
  'work': '工作',
  'school': '学习',
  'favorite': '收藏',
  'shopping': '购物',
  'music': '音乐',
  'game': '游戏',
  'home': '主页',
};

// 板块 ID 是否有效（内置 or 现有自定义板块）
bool boardExists(String id) {
  if (kBuiltInIds.contains(id)) return true;
  return Store.customBoards().any((b) => b.id == id);
}

// 由 ID 解析出板块元信息（含兜底，避免脏数据导致崩溃）
BoardMeta resolveBoard(String id) {
  switch (id) {
    case 'home':
      return const BoardMeta(id: 'home', label: '首页', icon: Icon(LucideNavIcons.home), page: HomePage());
    case 'news':
      return const BoardMeta(id: 'news', label: '日报', icon: Icon(LucideNavIcons.newspaper), page: NewsPage());
    case 'ai':
      return const BoardMeta(id: 'ai', label: 'AI 助手', icon: Icon(LucideNavIcons.sparkles), page: AiPage());
    case 'schedule':
      return const BoardMeta(id: 'schedule', label: '课程表', icon: Icon(LucideNavIcons.calendar), page: SchedulePage());
    case 'study':
      return const BoardMeta(id: 'study', label: '学习', icon: Icon(LucideNavIcons.bookOpen), page: StudyPage());
    case 'tools':
      return const BoardMeta(id: 'tools', label: '工具', icon: Icon(LucideNavIcons.sliders), page: ToolsPage());
    case 'settings':
      return const BoardMeta(id: 'settings', label: '设置', icon: Icon(LucideNavIcons.settings), page: SettingsPage());
    default:
      // 自定义板块：找不到就兜底成首页，保证导航不崩
      final b = Store.customBoards().where((x) => x.id == id).firstOrNull;
      if (b == null) {
        return const BoardMeta(id: 'home', label: '首页', icon: Icon(LucideNavIcons.home), page: HomePage());
      }
      return BoardMeta(
        id: b.id,
        label: b.name.isEmpty ? '我的板块' : b.name,
        icon: Icon(customIcon(b.iconName)),
        page: CustomBoardPage(boardId: b.id),
      );
  }
}

// 把导航配置（可能含脏数据）收敛成恰好 7 个有效板块，缺失的用未使用的内置补齐
List<BoardMeta> buildBoards(List<String> cfg) {
  final ids = cfg.where(boardExists).toList();
  final used = ids.toSet();
  for (final id in kBuiltInIds) {
    if (ids.length >= 7) break;
    if (!used.contains(id)) ids.add(id);
  }
  return ids.map(resolveBoard).toList();
}
