// 首页：待办 + 番茄钟 + 速记 + 常用入口 + 收藏
import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:url_launcher/url_launcher.dart';
import '../services/core.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _todoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<Todo> _todos = [];
  List<Note> _notes = [];
  List<Link> _links = [];
  List<Fav> _favs = [];
  bool _pomoRunning = false;
  int _pomoLeft = 25 * 60;
  DateTime? _pomoEnd; // 专注结束时刻（时间戳计时，后台/锁屏也不失真）
  Timer? _pomoTimer;

  void _reload() {
    setState(() {
      _todos = Store.todos();
      _notes = Store.notes();
      _links = Store.links();
      _favs = Store.favs();
    });
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _addTodo() {
    final t = _todoCtrl.text.trim();
    if (t.isEmpty) return;
    final l = Store.todos()..insert(0, Todo(t));
    Store.saveTodos(l);
    _todoCtrl.clear();
    _reload();
  }

  void _toggleTodo(int i) {
    final l = Store.todos();
    l[i].done = !l[i].done;
    Store.saveTodos(l);
    _reload();
  }

  void _delTodo(int i) {
    final l = Store.todos()..removeAt(i);
    Store.saveTodos(l);
    _reload();
  }

  void _clearDone() {
    final l = Store.todos().where((t) => !t.done).toList();
    Store.saveTodos(l);
    _reload();
  }

  void _addNote() {
    final t = _noteCtrl.text.trim();
    if (t.isEmpty) return;
    final l = Store.notes()..insert(0, Note(t, DateTime.now().millisecondsSinceEpoch));
    Store.saveNotes(l);
    _noteCtrl.clear();
    _reload();
  }

  void _delNote(int i) {
    final l = Store.notes()..removeAt(i);
    Store.saveNotes(l);
    _reload();
  }

  void _addLink() {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController(text: 'https://');
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加常用入口'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl1, decoration: const InputDecoration(labelText: '名称（如 抖音）')),
          const SizedBox(height: 8),
          TextField(controller: ctrl2, decoration: const InputDecoration(labelText: '链接地址')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final l = Store.links()..add(Link(ctrl1.text.trim(), ctrl2.text.trim()));
              Store.saveLinks(l);
              Navigator.pop(c);
              _reload();
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _pomoTick() {
    final left = _pomoEnd == null ? _pomoLeft : _pomoEnd!.difference(DateTime.now()).inSeconds;
    setState(() {
      _pomoLeft = left < 0 ? 0 : left;
      if (_pomoLeft <= 0) {
        _pomoEnd = null;
        _pomoRunning = false;
        _pomoTimer?.cancel();
        _pomoTimer = null;
        _pomoBeep();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🍅 专注完成！去把待办勾掉吧')));
      }
    });
  }

  void _pomoToggle() {
    setState(() {
      if (_pomoRunning) {
        // 暂停：记下剩余时间
        _pomoLeft = (_pomoEnd?.difference(DateTime.now()).inSeconds ?? _pomoLeft).clamp(0, 99999);
        _pomoEnd = null;
        _pomoRunning = false;
        _pomoTimer?.cancel();
        _pomoTimer = null;
      } else {
        _pomoEnd = DateTime.now().add(Duration(seconds: _pomoLeft));
        _pomoRunning = true;
        _pomoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pomoTick());
      }
    });
  }

  void _pomoReset() {
    _pomoTimer?.cancel();
    setState(() {
      _pomoRunning = false;
      _pomoEnd = null;
      _pomoLeft = 25 * 60;
    });
  }

  void _pomoBeep() {
    // 简单提示音：用 SystemSound（无第三方依赖）
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  String _pomoText() {
    final m = (_pomoLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_pomoLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final doneCount = _todos.where((t) => t.done).length;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---- 待办 + 番茄钟 ----
          _card(
            title: '✅ 待办清单 · 可勾选',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_todos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('$doneCount/${_todos.length} 已完成', style: TextStyle(fontSize: 12, color: c.outline)),
                ),
              ..._todos.asMap().entries.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(value: e.value.done, onChanged: (_) => _toggleTodo(e.key)),
                    title: Text(e.value.text, style: TextStyle(decoration: e.value.done ? TextDecoration.lineThrough : null, color: e.value.done ? c.outline : null)),
                    trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _delTodo(e.key)),
                  )),
              if (_todos.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('还没有待办。写一个今天要做的事…', style: TextStyle(color: c.outline, fontSize: 13))),
              TextField(
                controller: _todoCtrl,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(hintText: '写一条待办…', border: OutlineInputBorder()),
                onSubmitted: (_) => _addTodo(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton.tonal(onPressed: _addTodo, child: const Text('➕ 添加')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _clearDone, child: const Text('🧹 清除已完成')),
              ]),
              const Divider(height: 24),
              // 番茄钟
              Row(children: [
                Text(_pomoText(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()], color: c.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: _pomoLeft / (25 * 60), minHeight: 8, backgroundColor: c.surfaceContainerHighest),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _pomoToggle, child: Text(_pomoRunning ? '⏸ 暂停' : '▶ 开始')),
                const SizedBox(width: 6),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _pomoReset),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          // ---- 速记 ----
          _card(
            title: '📝 我的速记 · 随手记',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ..._notes.asMap().entries.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value.text),
                    trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _delNote(e.key)),
                  )),
              if (_notes.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('还没有速记。随手记一条想法…', style: TextStyle(color: c.outline, fontSize: 13))),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(hintText: '写一条想法 / 灵感…', border: OutlineInputBorder()),
                onSubmitted: (_) => _addNote(),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _addNote, child: const Text('➕ 添加')),
            ]),
          ),
          const SizedBox(height: 10),
          // ---- 常用入口 ----
          _card(
            title: '🔗 常用入口 · 一键直达',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _links.map((l) => ActionChip(
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text(l.label),
                      onPressed: () async {
                        await launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication);
                      },
                    )).toList(),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _addLink, icon: const Icon(Icons.add, size: 18), label: const Text('加一个')),
            ]),
          ),
          const SizedBox(height: 10),
          // ---- 收藏 ----
          _card(
            title: '⭐ 我的收藏 · 稍后读',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_favs.isEmpty)
                Text('还没有收藏。点新闻的 ☆ 收藏，稍后在这回看', style: TextStyle(color: c.outline, fontSize: 13))
              else
                ..._favs.asMap().entries.map((e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.value.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: e.value.source.isNotEmpty ? Text('${e.value.source} · ${_fmtDate(e.value.at)}') : null,
                      onTap: e.value.url.isNotEmpty ? () async => launchUrl(Uri.parse(e.value.url), mode: LaunchMode.externalApplication) : null,
                      trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _delFav(e.key)),
                    )),
              if (_favs.isNotEmpty) ...[
                const SizedBox(height: 4),
                TextButton(onPressed: () { Store.saveFavs([]); _reload(); }, child: const Text('🗑 清空收藏')),
              ],
            ]),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _delFav(int i) {
    final l = Store.favs()..removeAt(i);
    Store.saveFavs(l);
    _reload();
  }

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}-${d.day}';
  }

  Widget _card({required String title, required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        child,
      ])),
    );
  }
}
