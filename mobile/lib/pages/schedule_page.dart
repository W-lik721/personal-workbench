// 课程表页：手动加 / 按星期分组展示 / 删除
import 'package:flutter/material.dart';
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

  void _del(int i) {
    final l = Store.courses()..removeAt(i);
    Store.saveCourses(l);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final byDay = <String, List<int>>{}; // 星期 → 课程索引（避免 indexOf 查找）
    for (final d in _days) byDay[d] = [];
    for (var i = 0; i < _courses.length; i++) {
      final cr = _courses[i];
      final d = _days.contains(cr.dow) ? cr.dow : '其他';
      byDay[d]!.add(i);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Text('我的课程表 · ${_courses.length} 节', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Spacer(),
          FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('加一门')),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: _courses.isEmpty
            ? Center(child: Text('还没有课程。点右上角「加一门」', style: TextStyle(color: c.outline)))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: byDay.entries.map((e) {
                  if (e.value.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text('${e.key} · ${e.value.length} 节',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.outline)),
                    ),
                    ...e.value.map((idx) {
                      final cr = _courses[idx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          title: Text(cr.name.isEmpty ? '未命名' : cr.name),
                          subtitle: Text([
                            if (cr.time.isNotEmpty) cr.time,
                            if (cr.location.isNotEmpty) '📍 ${cr.location}',
                            if (cr.teacher.isNotEmpty) '👤 ${cr.teacher}',
                            if (cr.note.isNotEmpty) '📝 ${cr.note}',
                          ].join(' · ')),
                          trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _del(idx)),
                        ),
                      );
                    }),
                  ]);
                }).toList(),
              ),
      ),
    ]);
  }
}
