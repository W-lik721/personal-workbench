// 设置页：AI 助手记忆管理（开关/条数/长期记忆/清空历史）+ 外观
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../services/core.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _memOn = true;
  int _memMax = 20;
  int _memCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _memOn = Store.aiMemoryOn;
    _memMax = Store.aiMemoryMax;
    _memCount = Store.aiMemory().length;
  }

  void _reload() => setState(_refresh);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      // ---------- AI 记忆 ----------
      _sectionTitle('🤖 AI 助手记忆'),
      Card(
        child: Column(children: [
          SwitchListTile(
            title: const Text('记忆功能'),
            subtitle: const Text('打开后：自动记住聊天内容，下次打开还能接着聊；关掉则不再记新的'),
            value: _memOn,
            onChanged: (v) {
              Store.aiMemoryOn = v;
              _reload();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('对话记忆条数'),
            subtitle: Text('发送时最多带上最近 $_memMax 条聊天记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickMax(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: Text('长期记忆（$_memCount 条）'),
            subtitle: const Text('AI 回答下点「记住」会存到这里，每次对话都会带上'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _manageMemory,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: c.error),
            title: Text('清空对话历史', style: TextStyle(color: c.error)),
            subtitle: const Text('删掉所有聊天记录，AI 从此"失忆"（不影响长期记忆）'),
            onTap: _clearHistory,
          ),
        ]),
      ),

      // ---------- 外观 ----------
      _sectionTitle('🎨 外观'),
      Card(
        child:           ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            trailing: Switch(
              value: darkModeNotifier.value,
              onChanged: (v) => darkModeNotifier.value = v,
            ),
          ),
      ),

      // ---------- 数据备份 ----------
      _sectionTitle('💾 数据备份'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('把待办/速记/收藏/课程表等存成 JSON 文件（不含 API Key）'),
            onTap: _exportBackup,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导入恢复'),
            subtitle: const Text('从备份文件还原，会覆盖当前同类数据'),
            onTap: _importBackup,
          ),
        ]),
      ),

      // ---------- 关于 ----------
      _sectionTitle('ℹ️ 关于'),
      const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('轻量工作台'),
          subtitle: Text('v1.0 · 数据全部存手机本地，不上传\n日报/新闻来自公开接口，需联网'),
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  // 选择历史条数上限
  void _pickMax() {
    showDialog(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('对话记忆条数'),
        children: [10, 20, 30, 50, 100].map((n) {
          return SimpleDialogOption(
            onPressed: () {
              Store.aiMemoryMax = n;
              Navigator.pop(c);
              _reload();
            },
            child: Row(children: [
              Expanded(child: Text('最近 $n 条')),
              if (_memMax == n) const Icon(Icons.check, color: Colors.teal),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // 管理长期记忆：查看 / 删除 / 清空
  void _manageMemory() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) {
          final mem = Store.aiMemory();
          return AlertDialog(
            title: Row(children: [
              const Expanded(child: Text('长期记忆')),
              if (mem.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Store.saveAiMemory([]);
                    setDlg(() {});
                    _reload();
                  },
                  child: const Text('清空全部', style: TextStyle(color: Colors.redAccent)),
                ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: mem.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('还没有长期记忆。\n\n在 AI 助手里，AI 回答的下方点「记住」，重要信息就会存到这里。', textAlign: TextAlign.center),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: mem.length,
                      itemBuilder: (c, i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(mem[i], maxLines: 3, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: '删除这条',
                          onPressed: () {
                            final l = Store.aiMemory()..removeAt(i);
                            Store.saveAiMemory(l);
                            setDlg(() {});
                            _reload();
                          },
                        ),
                      ),
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
          );
        },
      ),
    );
  }

  // 清空对话历史
  void _clearHistory() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空对话历史？'),
        content: const Text('会删掉 AI 助手里所有聊天记录，之后 AI 不记得之前的对话了。这个操作不能撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              aiClearGlobal?.call();
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑 对话历史已清空')));
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  // 导出备份：系统文件选择器选位置，存成 JSON
  Future<void> _exportBackup() async {
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'workbench_backup_$stamp.json';
    String? path;
    try {
      path = await FilePicker.saveFile(
        dialogTitle: '保存备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开文件选择器')));
      return;
    }
    if (path == null) return; // 用户取消
    try {
      await File(path).writeAsString(jsonEncode(Store.exportAll()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ 已导出备份：$fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：${e.toString().replaceAll('Exception: ', '')}')));
    }
  }

  // 导入恢复：选 JSON 文件 → 校验 → 二次确认 → 还原
  Future<void> _importBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return; // 取消
    if (!mounted) return;
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('读不到文件内容')));
      return;
    }
    Map<String, dynamic> m;
    try {
      m = jsonDecode(utf8.decode(bytes, allowMalformed: true)) as Map<String, dynamic>;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件不是有效的备份 JSON')));
      return;
    }
    if (m['app'] != 'lite_workbench') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这不是本应用的备份文件')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text('导入会覆盖当前的待办 / 速记 / 收藏 / 课程表等数据，确定继续吗？\n\n（不会覆盖已设置的 API Key）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    Store.importAll(m);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已从备份恢复数据')));
  }
}
