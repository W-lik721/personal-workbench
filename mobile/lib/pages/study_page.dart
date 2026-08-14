// 学习中心：考试/假期倒计时 + GPA 计算 + 论文进度 + 闪卡复习
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../services/core.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  int _seg = 0; // 0 倒计时 / 1 GPA / 2 论文 / 3 闪卡

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习中心')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: SegmentedButton<int>(
            selected: {_seg},
            onSelectionChanged: (s) => setState(() => _seg = s.first),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('倒计时')),
              ButtonSegment(value: 1, label: Text('GPA')),
              ButtonSegment(value: 2, label: Text('论文')),
              ButtonSegment(value: 3, label: Text('闪卡')),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _seg,
            children: const [
              _CountdownTab(),
              _GpaTab(),
              _ThesisTab(),
              _FlashTab(),
            ],
          ),
        ),
      ]),
    );
  }
}

// 友好的倒计时文案
String _countdownText(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final target = DateTime(d.year, d.month, d.day);
  final days = target.difference(today).inDays;
  if (days == 0) return '就是今天';
  if (days > 0) return '还有 $days 天';
  return '已过 ${-days} 天';
}

// ============ ① 考试 / 假期倒计时 ============
class _CountdownTab extends StatefulWidget {
  const _CountdownTab();
  @override
  State<_CountdownTab> createState() => _CountdownTabState();
}
class _CountdownTabState extends State<_CountdownTab> {
  List<ExamEvent> _events = [];
  void _reload() => setState(() => _events = Store.events());
  @override
  void initState() { super.initState(); _reload(); }

  void _add() async {
    final nameCtrl = TextEditingController();
    DateTime? picked;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('添加倒计时'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: '名称（如 期末考试）', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(picked == null ? '选择日期' : '${picked!.month}月${picked!.day}日 ${picked!.year}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setD(() => picked = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || picked == null) return;
                final l = Store.events()..add(ExamEvent(nameCtrl.text.trim(), DateTime(picked!.year, picked!.month, picked!.day).millisecondsSinceEpoch));
                Store.saveEvents(l);
                Navigator.pop(c);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    _reload();
  }

  void _importPresets() async {
    final presets = Store.examPresets();
    final have = Store.events().map((e) => e.name).toSet();
    final avail = presets.where((p) => !have.contains(p.name)).toList();
    if (avail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('常用模板都已添加')));
      return;
    }
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('导入常用倒计时'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: avail.map((p) => ListTile(
            leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
            title: Text(p.name),
            subtitle: Text('${p.at == 0 ? '' : '${DateTime.fromMillisecondsSinceEpoch(p.at).month}月${DateTime.fromMillisecondsSinceEpoch(p.at).day}日'}（日期可改）'),
            onTap: () {
              final l = Store.events()..add(p);
              Store.saveEvents(l);
              Navigator.pop(c);
            },
          )).toList()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
      ),
    );
    _reload();
  }

  void _del(int i) {
    HapticFeedback.mediumImpact();
    final l = Store.events()..removeAt(i);
    Store.saveEvents(l);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final sorted = [..._events]..sort((a, b) => a.at.compareTo(b.at));
    final nearest = sorted.where((e) => e.at >= DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch).isEmpty
        ? (sorted.isEmpty ? null : sorted.last)
        : sorted.where((e) => e.at >= DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch).first;
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(12), children: [
        if (nearest != null)
          Card(
            color: c.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('最近', style: TextStyle(fontSize: 12, color: c.onPrimaryContainer.withValues(alpha: 0.7))),
                const SizedBox(height: 4),
                Row(children: [
                  Text(nearest.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(nearest.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                Text(_countdownText(nearest.at), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.primary)),
              ]),
            ),
          ),
        if (nearest != null) const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: FilledButton.tonal(onPressed: _importPresets, child: const Text('导入常用'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _add, child: const Text('自定义'))),
          ]),
        ),
        ...sorted.asMap().entries.map((e) => Dismissible(
              key: ObjectKey(e.value),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: c.error, child: const Icon(Icons.delete_outline, color: Colors.white)),
              onDismissed: (_) => _del(e.key),
              child: ListTile(
                leading: Text(e.value.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(e.value.name),
                subtitle: Text('${DateTime.fromMillisecondsSinceEpoch(e.value.at).month}月${DateTime.fromMillisecondsSinceEpoch(e.value.at).day}日'),
                trailing: Text(_countdownText(e.value.at), style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
              ),
            )),
        if (sorted.isEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Text('还没有倒计时。先「导入常用」或从四六级/考研/寒暑假挑一个。',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.outline, height: 1.5)),
        ),
        const SizedBox(height: 70),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton(onPressed: _add, tooltip: '添加倒计时', child: const Icon(Icons.add)),
      ),
    ]);
  }
}

// ============ ② GPA / 成绩计算 ============
class _GpaTab extends StatefulWidget {
  const _GpaTab();
  @override
  State<_GpaTab> createState() => _GpaTabState();
}
class _GpaTabState extends State<_GpaTab> {
  List<Grade> _grades = [];
  String _algo = Store.gpaAlgo;
  void _reload() => setState(() => _grades = Store.grades());
  @override
  void initState() { super.initState(); _reload(); }

  void _edit([Grade? g, int? idx]) async {
    final nameCtrl = TextEditingController(text: g?.name ?? '');
    final creditCtrl = TextEditingController(text: g != null ? g.credit.toString() : '');
    final scoreCtrl = TextEditingController(text: g != null ? g.score.toString() : '');
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(g == null ? '添加课程成绩' : '编辑成绩'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: '课程名', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: creditCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '学分', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: scoreCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '分数（百分制）', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final credit = double.tryParse(creditCtrl.text.trim());
              final score = double.tryParse(scoreCtrl.text.trim());
              if (name.isEmpty || credit == null || score == null) return;
              final l = Store.grades();
              final ng = Grade(name, credit, score);
              if (idx == null) {
                l.add(ng);
              } else {
                l[idx] = ng;
              }
              Store.saveGrades(l);
              Navigator.pop(c);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    _reload();
  }

  void _del(int i) {
    HapticFeedback.mediumImpact();
    final l = Store.grades()..removeAt(i);
    Store.saveGrades(l);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final r = Store.computeGpa(_grades, _algo);
    final algoNames = [...Store.gpaAlgos.keys, '5.0线性'];
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          const Text('绩点算法', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: _algo,
              isExpanded: true,
              items: algoNames.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _algo = v; Store.gpaAlgo = v; });
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_grades.isNotEmpty)
          Card(
            color: c.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('加权平均分', style: TextStyle(fontSize: 12)),
                  Text(r['avg']!.toStringAsFixed(1), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('GPA（$_algo）', style: const TextStyle(fontSize: 12)),
                  Text(r['gpa']!.toStringAsFixed(2), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ])),
                Column(children: [
                  Text('${_grades.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text('门课', style: TextStyle(fontSize: 12)),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        ..._grades.asMap().entries.map((e) => Dismissible(
              key: ObjectKey(e.value),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: c.error, child: const Icon(Icons.delete_outline, color: Colors.white)),
              onDismissed: (_) => _del(e.key),
              child: ListTile(
                title: Text(e.value.name),
                subtitle: Text('学分 ${e.value.credit.toStringAsFixed(1)} · 绩点 ${Store.scoreToGpaAlgo(_algo, e.value.score).toStringAsFixed(1)}'),
                trailing: Text(e.value.score.toStringAsFixed(0), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.primary)),
                onTap: () => _edit(e.value, e.key),
              ),
            )),
        if (_grades.isEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Text('还没有成绩。一门门录进去，自动算加权平均分和 GPA。',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.outline, height: 1.5)),
        ),
        const SizedBox(height: 70),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton(onPressed: () => _edit(), tooltip: '添加成绩', child: const Icon(Icons.add)),
      ),
    ]);
  }
}

// ============ ③ 论文进度 ============
class _ThesisTab extends StatefulWidget {
  const _ThesisTab();
  @override
  State<_ThesisTab> createState() => _ThesisTabState();
}
class _ThesisTabState extends State<_ThesisTab> {
  List<ThesisStage> _stages = [];
  void _reload() => setState(() => _stages = Store.thesisStages());
  @override
  void initState() { super.initState(); _reload(); }

  void _toggle(int i) async {
    final l = Store.thesisStages();
    final done = !l[i].done;
    DateTime? d;
    if (done) {
      d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
      if (d == null) return; // 取消不保存
    }
    l[i].done = done;
    l[i].at = done ? d!.millisecondsSinceEpoch : null;
    Store.saveThesis(l);
    _reload();
  }

  void _clearDate(int i) {
    final l = Store.thesisStages();
    l[i].at = null;
    Store.saveThesis(l);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final done = _stages.where((s) => s.done).length;
    final prog = _stages.isEmpty ? 0.0 : done / _stages.length;
    final labels = ['开题', '初稿', '查重', '答辩'];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('进度 $done/${_stages.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: prog, minHeight: 10, backgroundColor: c.surfaceContainerHighest)),
            const SizedBox(height: 12),
            Row(children: labels.asMap().entries.map((e) {
              final idx = e.key;
              final active = idx < done;
              return Expanded(
                child: Column(children: [
                  Icon(active ? Icons.check_circle : Icons.circle_outlined, color: active ? c.primary : c.outline, size: 22),
                  const SizedBox(height: 2),
                  Text(labels[idx], style: TextStyle(fontSize: 11, color: active ? c.primary : c.outline)),
                ]),
              );
            }).toList()),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ..._stages.asMap().entries.map((e) => Card(
            child: ListTile(
              leading: Icon(e.value.done ? Icons.check_circle : Icons.radio_button_unchecked, color: e.value.done ? c.primary : c.outline),
              title: Text(e.value.name, style: TextStyle(decoration: e.value.done ? TextDecoration.lineThrough : null, color: e.value.done ? c.outline : null)),
              subtitle: e.value.at != null ? Text('完成于 ${DateTime.fromMillisecondsSinceEpoch(e.value.at!).month}月${DateTime.fromMillisecondsSinceEpoch(e.value.at!).day}日') : const Text('点一下标记完成'),
              onTap: () => _toggle(e.key),
              trailing: e.value.at != null ? IconButton(icon: const Icon(Icons.event_busy_outlined, size: 18), onPressed: () => _clearDate(e.key)) : null,
            ),
          )),
      const SizedBox(height: 12),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('提示：点阶段标记完成并选日期，进度条自动推进。长按右侧图标可清空日期。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5)),
      ),
      const SizedBox(height: 20),
    ]);
  }
}

// ============ ④ 闪卡复习 ============
class _FlashTab extends StatefulWidget {
  const _FlashTab();
  @override
  State<_FlashTab> createState() => _FlashTabState();
}
class _FlashTabState extends State<_FlashTab> {
  List<Flashcard> _cards = [];
  bool _reviewing = false;
  List<Flashcard> _queue = [];
  int _qi = 0;
  bool _reveal = false;
  void _reload() => setState(() => _cards = Store.cards());
  @override
  void initState() { super.initState(); _reload(); }

  void _add() async {
    final frontCtrl = TextEditingController();
    final backCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建闪卡'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: frontCtrl, autofocus: true, decoration: const InputDecoration(labelText: '正面（问题 / 词）', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: backCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '背面（答案 / 释义）', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (frontCtrl.text.trim().isEmpty || backCtrl.text.trim().isEmpty) return;
              final l = Store.cards()..add(Flashcard(frontCtrl.text.trim(), backCtrl.text.trim()));
              Store.saveCards(l);
              Navigator.pop(c);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    _reload();
  }

  void _del(int i) {
    HapticFeedback.mediumImpact();
    final l = Store.cards()..removeAt(i);
    Store.saveCards(l);
    _reload();
  }

  void _startReview() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = Store.cards().where((c) => c.dueAt <= now).toList();
    if (due.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂时没有到期的卡，先建几张，过几天再来复习')));
      return;
    }
    setState(() { _reviewing = true; _queue = due; _qi = 0; _reveal = false; });
  }

  void _rate(int days) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final l = Store.cards();
    final cur = _queue[_qi];
    final idx = l.indexWhere((c) => c.front == cur.front && c.back == cur.back && c.createdAt == cur.createdAt);
    if (idx >= 0) {
      l[idx].dueAt = now + days * 86400000;
      l[idx].box = days >= 7 ? 3 : (days >= 3 ? 2 : 1);
      Store.saveCards(l);
    }
    if (_qi + 1 >= _queue.length) {
      setState(() => _reviewing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本轮复习完成！')));
      _reload();
    } else {
      setState(() { _qi++; _reveal = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (_reviewing && _queue.isNotEmpty) {
      final card = _queue[_qi];
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          LinearProgressIndicator(value: (_qi + 1) / _queue.length, backgroundColor: c.surfaceContainerHighest),
          const SizedBox(height: 8),
          Text('第 ${_qi + 1} / ${_queue.length} 张', style: TextStyle(color: c.outline)),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('正面', style: TextStyle(fontSize: 12, color: c.outline)),
                      const SizedBox(height: 6),
                      Text(card.front, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      if (_reveal) ...[
                        const Divider(height: 28),
                        Text('背面', style: TextStyle(fontSize: 12, color: c.outline)),
                        const SizedBox(height: 6),
                        Text(card.back, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_reveal)
            FilledButton.tonal(onPressed: () => setState(() => _reveal = true), child: const Text('显示答案'))
          else
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _rate(1), child: const Text('不会'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonal(onPressed: () => _rate(3), child: const Text('模糊'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: () => _rate(7), child: const Text('认识'))),
            ]),
        ]),
      );
    }
    final dueCount = _cards.where((c) => c.dueAt <= DateTime.now().millisecondsSinceEpoch).length;
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: c.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('共', style: TextStyle(fontSize: 12)),
                Text('${_cards.length} 张', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('待复习', style: TextStyle(fontSize: 12)),
                Text('$dueCount 张', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: dueCount > 0 ? c.primary : null)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(icon: const Icon(Icons.play_arrow), label: const Text('开始复习'), onPressed: _startReview),
        const SizedBox(height: 8),
        ..._cards.asMap().entries.map((e) => Dismissible(
              key: ObjectKey(e.value),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: c.error, child: const Icon(Icons.delete_outline, color: Colors.white)),
              onDismissed: (_) => _del(e.key),
              child: ListTile(
                title: Text(e.value.front),
                subtitle: Text(e.value.back, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: e.value.dueAt <= DateTime.now().millisecondsSinceEpoch ? Icon(Icons.notifications_active, color: c.primary, size: 18) : null,
              ),
            )),
        if (_cards.isEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Text('还没有闪卡。把要背的单词 / 公式 / 概念录进来，到期会提醒复习。',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.outline, height: 1.5)),
        ),
        const SizedBox(height: 70),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton(onPressed: _add, tooltip: '新建闪卡', child: const Icon(Icons.add)),
      ),
    ]);
  }
}
