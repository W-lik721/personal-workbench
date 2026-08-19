// 课程表页：手动加 / 按星期分组展示 / 删除 / 一键导入（粘贴或文件）
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:charset_converter/charset_converter.dart';
import '../services/core.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const _days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日', '其他'];
  List<Course> _courses = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _courses = Store.courses());

  void _add() {
    final dow = TextEditingController();
    final time = TextEditingController();
    final name = TextEditingController();
    final loc = TextEditingController();
    final teach = TextEditingController();
    final note = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('加一门课'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: dow, decoration: const InputDecoration(labelText: '星期（如 周一）')),
            TextField(controller: time, decoration: const InputDecoration(labelText: '时间（如 08:00-09:40）')),
            TextField(controller: name, decoration: const InputDecoration(labelText: '课程名 *')),
            TextField(controller: loc, decoration: const InputDecoration(labelText: '地点')),
            TextField(controller: teach, decoration: const InputDecoration(labelText: '老师')),
            TextField(controller: note, decoration: const InputDecoration(labelText: '备注')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty && time.text.trim().isEmpty && dow.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('至少填课程名或时间')));
                return;
              }
              Store.saveCourses([
                ...Store.courses(),
                Course(dow: dow.text.trim(), time: time.text.trim(), name: name.text.trim(),
                    location: loc.text.trim(), teacher: teach.text.trim(), note: note.text.trim()),
              ]);
              Navigator.pop(c);
              _reload();
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // 一键导入：粘贴多行文本，批量解析成课程
  void _import() {
    final cs = Theme.of(context).colorScheme;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('导入课程'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('每行一门课，支持两种格式：', style: TextStyle(fontSize: 13)),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
              child: const Text(
                '① 自由文本：周一 08:00-09:40 高等数学 @教三-201 张老师\n'
                '② Excel 粘贴（Tab 分列）：周一\\t08:00-09:40\\t高等数学\\t教三-201\\t张老师\n'
                '③ 或直接「选择文件」导入 .txt/.csv（自动识别 UTF-8 / GBK）',
                style: TextStyle(fontSize: 12),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _pickAndImport(),
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('选择文件导入'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 10,
              minLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '在此粘贴课程文本……\n例：周一 08:00-09:40 高等数学 @教三-201 张老师',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final parsed = _parseCourses(ctrl.text);
              if (parsed.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没解析到课程，检查格式')));
                return;
              }
              final n = _mergeImport(parsed);
              Navigator.pop(c);
              _reload();
              ScaffoldMessenger.of(context).showSnackBar(n == 0
                  ? const SnackBar(content: Text('没有新增（课程都已存在）'))
                  : SnackBar(content: Text('已导入 $n 节课程${parsed.length > n ? '（${parsed.length - n} 节重复已跳过）' : ''}')));
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  // 把粘贴文本解析为多门课；兼容 Tab 分列与自由文本两种格式
  List<Course> _parseCourses(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final out = <Course>[];
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      // 跳过纯表头行（如「星期 时间 课程 地点 老师」且无时间数字）
      if (!RegExp(r'\d{1,2}[:：]').hasMatch(line)) {
        final header = line.replaceAll(RegExp(r'[\s·:：,，、]'), '');
        if (RegExp(r'^(星期|时间|课程|地点|老师|备注)+$').hasMatch(header)) continue;
      }
      Course? cr;
      final tabs = line.split('\t');
      if (tabs.length > 1) {
        // Excel 列模式：星期 / 时间 / 课程 / 地点 / 老师 / 备注
        cr = Course(
          dow: tabs[0].trim(),
          time: tabs.length > 1 ? tabs[1].trim() : '',
          name: tabs.length > 2 ? tabs[2].trim() : '',
          location: tabs.length > 3 ? tabs[3].trim() : '',
          teacher: tabs.length > 4 ? tabs[4].trim() : '',
          note: tabs.length > 5 ? tabs[5].trim() : '',
        );
      } else {
        cr = _parseFreeLine(line);
      }
      if (cr != null && (cr.name.isNotEmpty || cr.time.isNotEmpty || cr.dow.isNotEmpty)) {
        out.add(cr);
      }
    }
    return out;
  }

  // 自由文本行解析：识别星期 / 时间 / 老师 / 地点，其余作课程名
  Course? _parseFreeLine(String line) {
    var s = line;
    String dow = '';
    String time = '';
    String teacher = '';
    String location = '';

    // 星期：周一…周日 / 星期一… / 礼拜一…
    final mDow = RegExp(r'(周[一二三四五六日天]|星期[一二三四五六日天]|礼拜[一二三四五六日天])').firstMatch(s);
    if (mDow != null) {
      dow = mDow.group(0)!;
      s = s.replaceFirst(mDow.group(0)!, ' ');
    }

    // 时间：08:00-09:40 / 8:00~9:40 / 08:00（中文冒号也兼容）
    final mTime = RegExp(r'\d{1,2}[:：]\d{2}\s*[-~–—]\s*\d{1,2}[:：]\d{2}|\d{1,2}[:：]\d{2}').firstMatch(s);
    if (mTime != null) {
      time = mTime.group(0)!.replaceAll('：', ':');
      s = s.replaceFirst(mTime.group(0)!, ' ');
    }

    // 老师：xxx老师
    final mTeach = RegExp(r'[\u4e00-\u9fa5]{1,4}老师').firstMatch(s);
    if (mTeach != null) {
      teacher = mTeach.group(0)!;
      s = s.replaceFirst(mTeach.group(0)!, ' ');
    }

    // 地点：@xxx 或 地点:xxx
    final mAt = RegExp(r'[@#](\S+)').firstMatch(s);
    if (mAt != null) {
      location = mAt.group(1)!;
      s = s.replaceFirst(mAt.group(0)!, ' ');
    }
    final mLoc = RegExp(r'地点[:：](\S+)').firstMatch(s);
    if (mLoc != null) {
      location = mLoc.group(1)!;
      s = s.replaceFirst(mLoc.group(0)!, ' ');
    }

    final name = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty && dow.isEmpty && time.isEmpty) return null;
    return Course(dow: dow, time: time, name: name, location: location, teacher: teacher);
  }

  // 从文件一键导入：选 .txt/.csv → 读字节 → 识别编码 → 复用解析逻辑
  Future<void> _pickAndImport() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'text', 'tsv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return; // 用户取消
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('读不到文件内容')));
      return;
    }
    final text = await _decode(bytes);
    final parsed = _parseCourses(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件没解析到课程，检查格式或编码')));
      return;
    }
    final n = _mergeImport(parsed);
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭导入弹窗
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(n == 0
        ? const SnackBar(content: Text('没有新增（课程都已存在）'))
        : SnackBar(content: Text('已导入 $n 节课程${parsed.length > n ? '（${parsed.length - n} 节重复已跳过）' : ''}')));
  }

  // 解码文件字节：先试 UTF-8，含替换符再走系统原生 GBK 兜底（Excel 默认 CSV 多为 GBK）
  Future<String> _decode(Uint8List bytes) async {
    final utf = utf8.decode(bytes, allowMalformed: true);
    if (utf.contains('\uFFFD')) {
      try {
        final gbk = await CharsetConverter.decode('GBK', bytes);
        if (gbk.isNotEmpty && !gbk.contains('\uFFFD')) return gbk;
      } catch (_) {
        // 原生编解码不可用则退回 UTF-8 结果
      }
    }
    return utf;
  }

  void _del(int i) {
    final removed = Store.courses()[i];
    final l = Store.courses()..removeAt(i);
    Store.saveCourses(l);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('已删除课程'),
      action: SnackBarAction(label: '撤销', onPressed: () {
        final cur = Store.courses();
        cur.insert(i.clamp(0, cur.length).toInt(), removed);
        Store.saveCourses(cur);
        _reload();
      }),
    ));
  }

  // 判断两门课是否重复（同一天 + 同一时间 + 同名）
  bool _same(Course a, Course b) => a.dow == b.dow && a.time == b.time && a.name == b.name;

  // 合并导入：跳过已存在 / 本次重复的课程，返回实际新增数量
  int _mergeImport(List<Course> parsed) {
    final existing = Store.courses();
    final added = <Course>[];
    for (final cr in parsed) {
      if (existing.any((e) => _same(e, cr)) || added.any((e) => _same(e, cr))) continue;
      added.add(cr);
    }
    if (added.isNotEmpty) Store.saveCourses([...existing, ...added]);
    return added.length;
  }

  // 提取开始时间（分钟数），用于同天课程排序；无法解析的排最前
  int _toMin(String t) {
    final m = RegExp(r'(\d{1,2})[:：](\d{2})').firstMatch(t);
    if (m == null) return 0;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  // 下一节：今天还没开始的最近一节（没有则返回 null）
  Widget? _nextCourseCard(ColorScheme c, String? todayKey, Map<String, List<int>> byDay) {
    if (todayKey == null) return null;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final upcoming = (byDay[todayKey] ?? [])
        .where((i) => _toMin(_courses[i].time) > nowMin)
        .map((i) => (idx: i, start: _toMin(_courses[i].time)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (upcoming.isEmpty) return null;
    final next = upcoming.first;
    final cr = _courses[next.idx];
    final mins = next.start - nowMin;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.schedule, color: c.primary),
        title: Text('下一节：${cr.name.isEmpty ? '未命名' : cr.name}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text([
          cr.time,
          if (cr.location.isNotEmpty) cr.location,
          '${mins ~/ 60 > 0 ? '${mins ~/ 60} 小时' : ''}${mins % 60} 分钟后开始',
        ].join(' · '), style: TextStyle(fontSize: 12, color: c.primary)),
        trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(next.idx)),
      ),
    );
  }

  // 清空全部课程（二次确认，防误触）
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空全部课程？'),
        content: Text('确定删除所有 ${_courses.length} 门课程吗？此操作不能撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      Store.saveCourses([]);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('课程表已清空')));
    }
  }

  // 编辑课程：预填当前字段，保存时替换第 i 项
  void _edit(int i) {
    final cr = Store.courses()[i];
    final dow = TextEditingController(text: cr.dow);
    final time = TextEditingController(text: cr.time);
    final name = TextEditingController(text: cr.name);
    final loc = TextEditingController(text: cr.location);
    final teach = TextEditingController(text: cr.teacher);
    final note = TextEditingController(text: cr.note);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑课程'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: dow, decoration: const InputDecoration(labelText: '星期（如 周一）')),
            TextField(controller: time, decoration: const InputDecoration(labelText: '时间（如 08:00-09:40）')),
            TextField(controller: name, decoration: const InputDecoration(labelText: '课程名 *')),
            TextField(controller: loc, decoration: const InputDecoration(labelText: '地点')),
            TextField(controller: teach, decoration: const InputDecoration(labelText: '老师')),
            TextField(controller: note, decoration: const InputDecoration(labelText: '备注')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Store.saveCourses([
                ...Store.courses().asMap().entries.map((e) => e.key == i
                    ? Course(dow: dow.text.trim(), time: time.text.trim(), name: name.text.trim(), location: loc.text.trim(), teacher: teach.text.trim(), note: note.text.trim())
                    : e.value),
              ]);
              Navigator.pop(c);
              _reload();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 当前星期对应的分组 key（用于高亮"今天"）
  String? _todayKey() {
    final w = DateTime.now().weekday; // 1=周一 ... 7=周日
    return (w >= 1 && w <= 7) ? _days[w - 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final todayKey = _todayKey();
    final byDay = <String, List<int>>{}; // 星期 → 课程索引（避免 indexOf 查找）
    for (final d in _days) {
      byDay[d] = [];
    }
    for (var i = 0; i < _courses.length; i++) {
      final cr = _courses[i];
      final d = _days.contains(cr.dow) ? cr.dow : '其他';
      byDay[d]!.add(i);
    }
    // 同一天课程按开始时间升序，方便看当天顺序
    for (final d in _days) {
      byDay[d]!.sort((a, b) => _toMin(_courses[a].time).compareTo(_toMin(_courses[b].time)));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.view_agenda_rounded, size: 20, color: c.primary),
                const SizedBox(width: 8),
                Text('我的课程表 · ${_courses.length} 节', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  onPressed: _import,
                  icon: const Icon(Icons.paste, size: 16),
                  label: const Text('导入', style: TextStyle(fontSize: 13)),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加', style: TextStyle(fontSize: 13)),
                ),
                if (_courses.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    onPressed: _clearAll,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _courses.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy_outlined, size: 48, color: c.outline.withValues(alpha: 0.6)),
                      const SizedBox(height: 16),
                      Text('还没有课程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onSurface)),
                      const SizedBox(height: 6),
                      Text('点右上角「加一门」或「导入」添加', textAlign: TextAlign.center, style: TextStyle(color: c.outline, height: 1.5)),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_nextCourseCard(c, todayKey, byDay) case final nextCard?) nextCard,
                  ...byDay.entries.map((e) {
                  if (e.value.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Container(
                        decoration: e.key == todayKey ? BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(6)) : null,
                        padding: e.key == todayKey ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2) : null,
                        child: Text('${e.key} · ${e.value.length} 节${e.key == todayKey ? ' · 今天' : ''}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: e.key == todayKey ? c.primary : c.outline)),
                      ),
                    ),
                    ...e.value.map((idx) {
                      final cr = _courses[idx];
                      return Dismissible(
                        key: ObjectKey(cr),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: c.error,
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) => _del(idx),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            onTap: () => _edit(idx),
                            title: Text(cr.name.isEmpty ? '未命名' : cr.name),
                            subtitle: Text([
                              if (cr.time.isNotEmpty) cr.time,
                              if (cr.location.isNotEmpty) cr.location,
                              if (cr.teacher.isNotEmpty) cr.teacher,
                              if (cr.note.isNotEmpty) cr.note,
                            ].join(' · ')),
                            trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(idx)),
                          ),
                        ),
                      );
                    }),
                  ]);
                }),
                ],
              ),
      ),
    ]);
  }
}
