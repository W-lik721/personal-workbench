// 首页：待办 + 番茄钟 + 速记 + 常用入口 + 收藏
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType, HapticFeedback;
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/core.dart';
import '../services/notifier.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _todoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _noteQCtl = TextEditingController(); // 速记搜索
  final _favQCtl = TextEditingController(); // 收藏搜索
  String _noteQ = '';
  String _favQ = '';
  List<Todo> _todos = [];
  List<Note> _notes = [];
  List<Fav> _favs = [];
  List<ExamEvent> _events = [];
  bool _pomoRunning = false;
  int _pomoLeft = 25 * 60;
  int _pomoTotal = 25 * 60; // 当前选择的专注总时长（进度条分母 + 重置基准）
  DateTime? _pomoEnd; // 专注结束时刻（时间戳计时，后台/锁屏也不失真）
  Timer? _pomoTimer;
  final stt.SpeechToText _speech = stt.SpeechToText(); // 语音速记（系统语音识别，免 key）
  bool _listening = false; // 是否正在录音

  void _reload() {
    setState(() {
      _todos = Store.todos();
      _notes = Store.notes();
      _favs = Store.favs();
      _events = Store.events();
    });
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _restorePomo();
  }

  // 跨进程恢复番茄钟：App 被系统杀掉再开，进行中/暂停的计时还能接着
  void _restorePomo() {
    final end = Store.pomoEndMs;
    if (end != null && end > DateTime.now().millisecondsSinceEpoch) {
      // 进行中：恢复结束时刻并自动续跑
      _pomoEnd = DateTime.fromMillisecondsSinceEpoch(end);
      _pomoTotal = Store.pomoTotalSec;
      _pomoLeft = (_pomoEnd!.difference(DateTime.now()).inSeconds).clamp(0, 99999);
      _pomoRunning = true;
      _pomoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pomoTick());
    } else {
      // 暂停态或已结束：恢复剩余秒数（若有），否则用默认/上次时长
      _pomoTotal = Store.pomoTotalSec;
      _pomoLeft = Store.pomoLeftSec ?? _pomoTotal;
      Store.pomoEndMs = null; // 清理过期的"进行中"标记
    }
  }

  @override
  void dispose() {
    _speech.stop(); // 离开页面时停止录音，释放麦克风
    _todoCtrl.dispose();
    _noteCtrl.dispose();
    _noteQCtl.dispose();
    _favQCtl.dispose();
    super.dispose();
  }

  // 语音速记：点一下开始听，再点停止；识别结果实时填入速记框
  Future<void> _toggleSpeech() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('语音识别不可用：手机上没装语音引擎，或没开麦克风权限')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(localeId: 'zh_CN'),
      onResult: (r) {
        final t = r.recognizedWords;
        if (t.isNotEmpty && mounted) _noteCtrl.text = t;
      },
    );
  }

  void _addTodo() {
    final t = _todoCtrl.text.trim();
    if (t.isEmpty) return;
    HapticFeedback.selectionClick(); // 轻触感：添加成功
    final l = Store.todos()..insert(0, Todo(t));
    Store.saveTodos(l);
    _todoCtrl.clear();
    _reload();
  }

  void _toggleTodo(int i) {
    HapticFeedback.selectionClick(); // 轻触感：勾选/取消勾选
    final l = Store.todos();
    l[i].done = !l[i].done;
    // 勾选完成 → 取消该待办的提醒
    if (l[i].done && l[i].remindAt != null) Notifier.cancelTodo(l[i].remindAt!);
    Store.saveTodos(l);
    _reload();
  }

  void _delTodo(int i) {
    final removed = Store.todos()[i];
    if (removed.remindAt != null) Notifier.cancelTodo(removed.remindAt!);
    HapticFeedback.mediumImpact(); // 重点触感：删除
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
    HapticFeedback.selectionClick(); // 轻触感：添加成功
    final l = Store.notes()..insert(0, Note(t, DateTime.now().millisecondsSinceEpoch));
    Store.saveNotes(l);
    _noteCtrl.clear();
    _reload();
  }

  void _delNote(int i) {
    final removed = Store.notes()[i];
    HapticFeedback.mediumImpact(); // 重点触感：删除
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
  Widget _stat(ColorScheme c, String label, int n) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          _AnimatedCount(value: n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.primary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: c.outline)),
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
        Store.pomoEndMs = null;
        Store.pomoLeftSec = null;
        Store.addStudyMinutes(_pomoTotal ~/ 60); // 学习打卡：累计时长 + 连续天数
        _pomoBeep();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('专注完成！去把待办勾掉吧')));
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
        Store.pomoEndMs = null;
        Store.pomoLeftSec = _pomoLeft;
      } else {
        _pomoEnd = DateTime.now().add(Duration(seconds: _pomoLeft));
        _pomoRunning = true;
        _pomoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pomoTick());
        Store.pomoEndMs = _pomoEnd!.millisecondsSinceEpoch;
        Store.pomoTotalSec = _pomoTotal;
        Store.pomoLeftSec = null;
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
    Store.pomoEndMs = null;
    Store.pomoLeftSec = null;
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
    // 速记/收藏搜索过滤（关键词为空时显示全部）
    final visNotes = _noteQ.isEmpty ? _notes : _notes.where((n) => n.text.contains(_noteQ)).toList();
    final visFavs = _favQ.isEmpty ? _favs : _favs.where((f) => f.title.contains(_favQ)).toList();
    // 待办：未完成优先、完成项自动沉底（保持各自原顺序）
    final visTodos = [..._todos.where((t) => !t.done), ..._todos.where((t) => t.done)];
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---- 待办 + 番茄钟 ----
          _card(
            title: '待办清单 · 可勾选',
            foldKey: 'todo',
            icon: Icons.checklist_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_todos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('$doneCount/${_todos.length} 已完成', style: TextStyle(fontSize: 12, color: c.outline)),
                ),
              ...visTodos.map((t) {
                final i = _todos.indexOf(t); // 排序后取原始索引，保证删/改/勾选正确
                return Dismissible(
                  key: ObjectKey(t),
                  direction: DismissDirection.endToStart,
                  background: _swipeBg(c),
                  onDismissed: (_) => _delTodo(i),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(value: t.done, onChanged: (_) => _toggleTodo(i)),
                    title: GestureDetector(
                      onTap: () => _editTodo(i),
                      child: Text(t.text, style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null, color: t.done ? c.outline : null)),
                    ),
                    subtitle: t.remindAt != null
                        ? Text(_fmtRemind(t.remindAt!), style: TextStyle(fontSize: 11, color: c.primary))
                        : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: '提醒',
                        icon: Icon(Icons.alarm_add, size: 20, color: t.remindAt != null ? c.primary : c.outline),
                        onPressed: () => _setRemind(i),
                      ),
                      const SizedBox(width: 2),
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editTodo(i)),
                    ]),
                  ),
                );
              }),
              if (_todos.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('还没有待办。写一个今天要做的事…', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13))),
              TextField(
                controller: _todoCtrl,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(hintText: '写一条待办…', border: OutlineInputBorder()),
                onSubmitted: (_) => _addTodo(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton.tonal(onPressed: _addTodo, child: const Text('添加')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _clearDone, child: const Text('清除已完成')),
              ]),
              const Divider(height: 24),
              // 番茄钟
              Row(children: [
                const Text('专注计时', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                    Store.pomoTotalSec = _pomoTotal;
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
                FilledButton(onPressed: _pomoToggle, child: Text(_pomoRunning ? '暂停' : '开始')),
                const SizedBox(width: 6),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _pomoReset),
              ]),
            ]),
          ),
          const SizedBox(height: 8),
          // ---- 速记 ----
          _card(
            title: '我的速记 · 随手记',
            foldKey: 'note',
            icon: Icons.edit_note_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_notes.length > 3) ...[
                TextField(
                  controller: _noteQCtl,
                  decoration: const InputDecoration(
                    hintText: '搜速记…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _noteQ = v.trim()),
                ),
                const SizedBox(height: 6),
              ],
              ...visNotes.asMap().entries.map((e) => Dismissible(
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
              if (visNotes.isEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_noteQ.isEmpty ? '还没有速记。随手记一条想法…' : '没有匹配「$_noteQ」的速记', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13))),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(hintText: '写一条想法 / 灵感…', border: OutlineInputBorder()),
                      onSubmitted: (_) => _addNote(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _listening ? '停止录音' : '语音速记（说中文转文字）',
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? c.error : null),
                    onPressed: _toggleSpeech,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _addNote, child: const Text('添加')),
            ]),
          ),
          const SizedBox(height: 8),
          // ---- 今日概览（替换原"常用入口"） ----
          _card(
            title: '今日概览',
            foldKey: 'overview',
            icon: Icons.insights_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _stat(c, '待做', _todos.where((t) => !t.done).length),
                _stat(c, '速记', _notes.length),
                _stat(c, '收藏', _favs.length),
              ]),
              // 学习打卡：今日番茄钟时长 + 连续天数
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.local_fire_department, size: 15, color: Store.studyStreak > 0 ? const Color(0xFFF0A858) : c.outline),
                  const SizedBox(width: 4),
                  Text('今日专注 ${Store.studySecondsToday ~/ 60} 分钟 · 连续打卡 ${Store.studyStreak} 天',
                      style: TextStyle(fontSize: 12, color: Store.studyStreak > 0 ? c.primary : c.outline)),
                ]),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('让 AI 给我今日灵感'),
                  onPressed: _aiInspire,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          // ---- 最近倒计时（跳学习中心） ----
          _card(
            title: '最近倒计时',
            foldKey: 'countdown',
            icon: Icons.hourglass_top_rounded,
            child: _events.isEmpty
                ? InkWell(
                    onTap: () => switchTabGlobal?.call(4),
                    child: Text('还没设倒计时。去「学习」页导入四六级/考研/寒暑假 →', style: TextStyle(color: c.outline, fontSize: 13)),
                  )
                : InkWell(
                    onTap: () => switchTabGlobal?.call(4),
                    child: Builder(builder: (ctx) {
                      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch;
                      final future = _events.where((e) => e.at >= today).toList()..sort((a, b) => a.at.compareTo(b.at));
                      final nearest = future.isNotEmpty ? future.first : (_events..sort((a, b) => b.at.compareTo(a.at))).first;
                      final d = DateTime.fromMillisecondsSinceEpoch(nearest.at);
                      final diff = DateTime(d.year, d.month, d.day).difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
                      final txt = diff == 0 ? '就是今天' : (diff > 0 ? '还有 $diff 天' : '已过 ${-diff} 天');
                      return Row(children: [
                        Text(nearest.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(nearest.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                        Text(txt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.primary)),
                      ]);
                    }),
                  ),
          ),
          const SizedBox(height: 8),
          // ---- 收藏 ----
          _card(
            title: '我的收藏 · 稍后读',
            foldKey: 'fav',
            icon: Icons.bookmark_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_favs.length > 3) ...[
                TextField(
                  controller: _favQCtl,
                  decoration: const InputDecoration(
                    hintText: '搜收藏…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _favQ = v.trim()),
                ),
                const SizedBox(height: 6),
              ],
              if (_favs.isEmpty)
                Text('还没有收藏。点新闻的收藏，稍后在这回看', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13))
              else if (visFavs.isEmpty)
                Text('没有匹配「$_favQ」的收藏', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13))
              else
                ...visFavs.asMap().entries.map((e) => Dismissible(
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
                TextButton(onPressed: () { Store.saveFavs([]); _reload(); }, child: const Text('清空收藏')),
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
    HapticFeedback.mediumImpact(); // 重点触感：删除
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

  // 设置/修改/取消待办提醒（点提醒按钮）
  void _setRemind(int i) {
    final todo = Store.todos()[i];
    if (todo.remindAt == null) {
      _pickRemind(i);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('提醒时间：${_fmtRemind(todo.remindAt!)}')),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('修改时间'),
            onTap: () {
              Navigator.pop(c);
              _pickRemind(i);
            },
          ),
          ListTile(
            leading: const Icon(Icons.alarm_off_outlined),
            title: const Text('取消提醒'),
            onTap: () {
              Navigator.pop(c);
              _cancelRemind(i);
            },
          ),
        ]),
      ),
    );
  }

  // 选日期 + 时间，保存并安排系统通知
  void _pickRemind(int i) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: '选择提醒日期',
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: '选择提醒时间',
    );
    if (t == null || !mounted) return;
    final when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final l = Store.todos();
    final oldAt = l[i].remindAt;
    l[i].remindAt = when.millisecondsSinceEpoch;
    Store.saveTodos(l);
    await Notifier.scheduleTodo(when.millisecondsSinceEpoch, l[i].text);
    if (oldAt != null) await Notifier.cancelTodo(oldAt);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已设置提醒：${_fmtRemind(when.millisecondsSinceEpoch)}')));
  }

  // 取消提醒（仅清本地字段 + 取消系统通知）
  void _cancelRemind(int i) async {
    final l = Store.todos();
    final oldAt = l[i].remindAt;
    l[i].remindAt = null;
    Store.saveTodos(l);
    if (oldAt != null) await Notifier.cancelTodo(oldAt);
    _reload();
  }

  // 提醒时间的友好显示："今天 14:30" / "8月15日 09:00"
  String _fmtRemind(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return '今天 $hm';
    return '${d.month}月${d.day}日 $hm';
  }

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
            onPressed: () async {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                Navigator.pop(c);
                return;
              }
              final l = Store.todos();
              l[i].text = t;
              // 已设提醒 → 同步更新通知里的文字（同 id 覆盖）
              if (l[i].remindAt != null) await Notifier.scheduleTodo(l[i].remindAt!, t);
              Store.saveTodos(l);
              if (c.mounted) Navigator.pop(c);
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

  // 折叠状态：foldKey 存在即可点标题收起（长页面可收次要卡片）
  final Set<String> _folded = {};

  Widget _card({required String title, required Widget child, String? foldKey, IconData? icon}) {
    final folded = foldKey != null && _folded.contains(foldKey);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            if (foldKey != null)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() {
                  folded ? _folded.remove(foldKey) : _folded.add(foldKey);
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(folded ? Icons.expand_more : Icons.expand_less, size: 18, color: Theme.of(context).colorScheme.outline),
                ),
              ),
          ]),
          if (!folded) ...[
            const SizedBox(height: 8),
            child,
          ],
        ]),
      ),
    );
  }
}

// 数字从旧值平滑滚动到新值（避免每次 setState 从 0 硬跳）
class _AnimatedCount extends StatefulWidget {
  final int value;
  final TextStyle style;
  const _AnimatedCount({required this.value, required this.style});
  @override
  State<_AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<_AnimatedCount> {
  late int _last = widget.value;
  @override
  void didUpdateWidget(covariant _AnimatedCount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _last = old.value; // 记住旧值作为动画起点
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _last, end: widget.value),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (c, v, _) => Text('$v', style: widget.style),
    );
  }
}
