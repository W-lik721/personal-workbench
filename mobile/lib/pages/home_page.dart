// 首页：待办 + 番茄钟 + 速记 + 常用入口 + 收藏
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType, HapticFeedback;
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
  List<Fav> _favs = [];
  bool _pomoRunning = false;
  int _pomoLeft = 25 * 60;
  int _pomoTotal = 25 * 60; // 当前选择的专注总时长（进度条分母 + 重置基准）
  DateTime? _pomoEnd; // 专注结束时刻（时间戳计时，后台/锁屏也不失真）
  Timer? _pomoTimer;

  void _reload() {
    setState(() {
      _todos = Store.todos();
      _notes = Store.notes();
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
    final removed = Store.todos()[i];
    final l = Store.todos()..removeAt(i);
    Store.saveTodos(l);
    _reload();
    _undoSnack('已删除待办', () {
      final l2 = Store.todos();
      final idx = i.clamp(0, l2.length);
      l2.insert(idx, removed);
      Store.saveTodos(l2);
      _reload();
    });
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
    final removed = Store.notes()[i];
    final l = Store.notes()..removeAt(i);
    Store.saveNotes(l);
    _reload();
    _undoSnack('已删除速记', () {
      final l2 = Store.notes();
      final idx = i.clamp(0, l2.length);
      l2.insert(idx, removed);
      Store.saveNotes(l2);
      _reload();
    });
  }

  // 今日概览的小数字卡片
  Widget _stat(ColorScheme c, String icon, String label, int n) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.primary)),
          const SizedBox(height: 2),
          Text('$icon $label', style: TextStyle(fontSize: 12, color: c.outline)),
        ]),
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
      _pomoLeft = _pomoTotal;
    });
  }

  void _pomoBeep() {
    // 结束提醒：震动 + 提示音，比单一的轻微提示音更不容易错过
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
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
              ..._todos.asMap().entries.map((e) => Dismissible(
                    key: ObjectKey(e.value),
                    direction: DismissDirection.endToStart,
                    background: _swipeBg(c),
                    onDismissed: (_) => _delTodo(e.key),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(value: e.value.done, onChanged: (_) => _toggleTodo(e.key)),
                      title: GestureDetector(
                        onTap: () => _editTodo(e.key),
                        child: Text(e.value.text, style: TextStyle(decoration: e.value.done ? TextDecoration.lineThrough : null, color: e.value.done ? c.outline : null)),
                      ),
                      trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editTodo(e.key)),
                    ),
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
                const Text('🍅 专注计时', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                DropdownButton<int>(
                  value: _pomoTotal ~/ 60,
                  items: const [5, 15, 25, 45].map((m) => DropdownMenuItem(value: m, child: Text('$m 分钟'))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _pomoTotal = v * 60;
                      if (!_pomoRunning) _pomoLeft = _pomoTotal;
                    });
                  },
                ),
              ]),
              Row(children: [
                Text(_pomoText(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()], color: c.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: _pomoLeft / _pomoTotal, minHeight: 8, backgroundColor: c.surfaceContainerHighest),
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
              ..._notes.asMap().entries.map((e) => Dismissible(
                    key: ObjectKey(e.value),
                    direction: DismissDirection.endToStart,
                    background: _swipeBg(c),
                    onDismissed: (_) => _delNote(e.key),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _editNote(e.key),
                      title: Text(e.value.text),
                      trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editNote(e.key)),
                    ),
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
          // ---- 今日概览（替换原"常用入口"） ----
          _card(
            title: '📊 今日概览',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _stat(c, '✅', '待做', _todos.where((t) => !t.done).length),
                _stat(c, '📝', '速记', _notes.length),
                _stat(c, '⭐', '收藏', _favs.length),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('💡 让 AI 给我今日灵感'),
                  onPressed: _aiInspire,
                ),
              ),
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
                ..._favs.asMap().entries.map((e) => Dismissible(
                      key: ObjectKey(e.value),
                      direction: DismissDirection.endToStart,
                      background: _swipeBg(c),
                      onDismissed: (_) => _delFav(e.key),
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: e.value.source.isNotEmpty ? Text('${e.value.source} · ${_fmtDate(e.value.at)}') : null,
                        onTap: e.value.url.isNotEmpty ? () async => launchUrl(Uri.parse(e.value.url), mode: LaunchMode.externalApplication) : null,
                      ),
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
    final removed = Store.favs()[i];
    final l = Store.favs()..removeAt(i);
    Store.saveFavs(l);
    _reload();
    _undoSnack('已删除收藏', () {
      final l2 = Store.favs();
      final idx = i.clamp(0, l2.length);
      l2.insert(idx, removed);
      Store.saveFavs(l2);
      _reload();
    });
  }

  // 让 AI 根据今天的待办/速记给 1-2 个可动手的小建议（替换原"常用入口"的用处）
  void _aiInspire() {
    if (aiAskGlobal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 还没准备好，去设置里填好 Key 再试')));
      return;
    }
    final pending = _todos.where((t) => !t.done).map((t) => t.text).take(8).toList();
    final notes = _notes.map((n) => n.text).take(5).toList();
    final b = StringBuffer();
    b.writeln('这是我今天工作台的状态：');
    b.writeln('待办（还没做的）：${pending.isEmpty ? '暂无' : pending.join('、')}');
    b.writeln('随手记：${notes.isEmpty ? '暂无' : notes.join('、')}');
    b.writeln('请基于上面这些，给我 1-2 个今天可以马上动手做的具体小建议或灵感，用大白话、别太啰嗦。');
    aiAskGlobal!(b.toString());
  }

  // 删除后通用的"撤销"SnackBar（待办/速记/收藏复用，避免误删找不回）
  void _undoSnack(String msg, VoidCallback undo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: '撤销', onPressed: undo),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // 侧滑删除的红色背景（与移动端原生手感一致）
  Widget _swipeBg(ColorScheme c) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: c.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      );

  // 编辑已有待办（点文字或铅笔图标）
  void _editTodo(int i) {
    final cur = Store.todos()[i];
    final ctrl = TextEditingController(text: cur.text);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑待办'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          minLines: 1,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                Navigator.pop(c);
                return;
              }
              final l = Store.todos();
              l[i].text = t;
              Store.saveTodos(l);
              Navigator.pop(c);
              _reload();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 编辑已有速记（点文字或铅笔图标）
  void _editNote(int i) {
    final cur = Store.notes()[i];
    final ctrl = TextEditingController(text: cur.text);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑速记'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                Navigator.pop(c);
                return;
              }
              final l = Store.notes();
              l[i].text = t;
              Store.saveNotes(l);
              Navigator.pop(c);
              _reload();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
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
