// 全局搜索页：跨模块本地搜索（待办 / 速记 / 收藏 / 常用入口 / 课程 / AI 对话 / 账号）
// 入口：首页顶部搜索条；点结果切到对应底部板块（用 switchTabGlobal，按板块 id 查 index，不硬编码）
import 'package:flutter/material.dart';
import '../services/core.dart';
import '../boards.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

// 搜索结果条目
class _Hit {
  final String group; // 模块名（分组标题）
  final String title; // 主文本
  final String sub; // 副文本
  final IconData icon;
  final String board; // 点击后跳转的板块 id
  const _Hit(this.group, this.title, this.sub, this.icon, this.board);
}

class _SearchPageState extends State<SearchPage> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  String _kw = '';
  List<Account> _accounts = const []; // accounts() 是异步的，进页预加载一次

  @override
  void initState() {
    super.initState();
    // 进页自动弹键盘（addPostFrameCallback 保证布局就绪）
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final l = await Store.accounts();
    if (mounted) setState(() => _accounts = l);
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  // 本地即时过滤：7 类数据源全部同步读，无网络
  List<_Hit> _search(String kw) {
    final k = kw.trim().toLowerCase();
    if (k.isEmpty) return const [];
    final hits = <_Hit>[];
    bool m(String? s) => s != null && s.isNotEmpty && s.toLowerCase().contains(k);

    for (final t in Store.todos()) {
      if (m(t.text)) hits.add(_Hit('待办', t.text, t.done ? '已完成' : '未完成', Icons.checklist_rounded, 'home'));
    }
    for (final n in Store.notes()) {
      if (m(n.text)) hits.add(_Hit('速记', n.text, '', Icons.note_rounded, 'home'));
    }
    for (final f in Store.favs()) {
      if (m(f.title) || m(f.url)) hits.add(_Hit('收藏', f.title, f.source, Icons.star_rounded, 'home'));
    }
    for (final l in Store.links()) {
      if (m(l.label) || m(l.url)) hits.add(_Hit('常用入口', l.label, l.url, Icons.link_rounded, 'home'));
    }
    for (final c in Store.courses()) {
      if (m(c.name) || m(c.location) || m(c.teacher) || m(c.note)) {
        final sub = [c.dow, c.time, c.location].where((s) => s.isNotEmpty).join(' · ');
        hits.add(_Hit('课程', c.name.isEmpty ? '(未命名课程)' : c.name, sub, Icons.calendar_month_rounded, 'schedule'));
      }
    }
    for (final h in Store.aiHistory()) {
      final content = h['content'] ?? '';
      if (m(content)) {
        final title = content.length > 60 ? '${content.substring(0, 60)}…' : content;
        hits.add(_Hit('AI 对话', title, h['role'] == 'assistant' ? 'AI 回复' : '我的提问', Icons.smart_toy_rounded, 'ai'));
      }
    }
    for (final a in _accounts) {
      if (m(a.title) || m(a.username) || m(a.note)) {
        final sub = [a.username, a.note].where((s) => s.isNotEmpty).join(' · ');
        hits.add(_Hit('账号', a.title, sub, Icons.key_rounded, 'tools'));
      }
    }
    return hits;
  }

  // 点结果：按板块 id 查底部导航 index，切页后关闭搜索页
  void _go(String boardId) {
    final boards = buildBoards(Store.navConfig);
    final idx = boards.indexWhere((b) => b.id == boardId);
    switchTabGlobal?.call(idx); // 全局可变变量不 promotion，用 ?. 安全调用
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final hits = _search(_kw);
    // 按模块分组（保持 待办→速记→收藏→入口→课程→AI→账号 顺序）
    final groups = <String, List<_Hit>>{};
    for (final h in hits) {
      groups.putIfAbsent(h.group, () => []).add(h);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          focusNode: _focus,
          autofocus: true,
          onChanged: (v) => setState(() => _kw = v),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索待办 / 速记 / 收藏 / 课程 / 账号…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_kw.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清空',
              onPressed: () {
                _q.clear();
                setState(() => _kw = '');
              },
            ),
        ],
      ),
      body: _kw.trim().isEmpty
          ? _empty(c, '输入关键词，跨模块搜索本机数据')
          : hits.isEmpty
              ? _empty(c, '没有匹配的结果')
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final e in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text('${e.key}（${e.value.length}）',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c.primary)),
                      ),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(children: [
                          for (var i = 0; i < e.value.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              leading: Icon(e.value[i].icon, size: 20, color: c.primary),
                              title: Text(e.value[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: e.value[i].sub.isNotEmpty
                                  ? Text(e.value[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis)
                                  : null,
                              onTap: () => _go(e.value[i].board),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _empty(ColorScheme c, String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded, size: 48, color: c.outline),
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: c.outline)),
        ]),
      );
}
