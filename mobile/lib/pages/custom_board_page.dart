// 自定义板块页：按 boardId 展示一个命名板块，里面是一列条目（链接 / 笔记）。
// 链接 → 点开跳系统浏览器（不嵌 App）；笔记 → 点开弹窗看正文。
// 可：改板块名 / 换图标 / 增删条目 / 上下拖动排序。
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/core.dart';
import '../boards.dart';
import '../nav_notifier.dart';

class CustomBoardPage extends StatefulWidget {
  final String boardId;
  const CustomBoardPage({super.key, required this.boardId});
  @override
  State<CustomBoardPage> createState() => _CustomBoardPageState();
}

class _CustomBoardPageState extends State<CustomBoardPage> {
  late CustomBoard _board;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final b = Store.customBoards().where((x) => x.id == widget.boardId).firstOrNull;
    if (b == null) {
      setState(() => _missing = true);
      return;
    }
    setState(() => _board = b);
  }

  void _save() => Store.saveCustomBoards(
        Store.customBoards().map((b) => b.id == _board.id ? _board : b).toList(),
      );

  // 删除整个板块：同步把导航里引用它的位置换成未使用的内置板块，保证仍是 7 个
  Future<void> _deleteBoard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这个板块？'),
        content: Text('会删掉「${_board.name}」以及里面的 ${_board.items.length} 条内容，且从底部导航移除。此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Store.saveCustomBoards(Store.customBoards().where((b) => b.id != widget.boardId).toList());
    // 导航自愈：把失效的槽位补成未使用的内置板块
    final nav = Store.navConfig;
    final keep = nav.where((id) => id != widget.boardId && boardExists(id)).toSet();
    final healed = <String>[];
    for (final id in nav) {
      if (id == widget.boardId || !boardExists(id)) {
        final unused = kBuiltInIds.firstWhere(
          (b) => !keep.contains(b) && !healed.contains(b),
          orElse: () => 'home',
        );
        healed.add(unused);
        keep.add(unused);
      } else {
        healed.add(id);
      }
    }
    Store.navConfig = healed;
    navConfigNotifier.value++;
    if (mounted) Navigator.pop(context);
  }

  // 改板块名 + 图标
  void _editBoardMeta() {
    final nameCtrl = TextEditingController(text: _board.name);
    String iconName = _board.iconName;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('板块设置'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: nameCtrl,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '板块名（最多 6 字）', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            const Text('图标', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: customIconOptions.entries.map((e) {
                final selected = iconName == e.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setDlg(() => iconName = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                      border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(customIcon(e.key), size: 18, color: selected ? Theme.of(context).colorScheme.primary : null),
                      const SizedBox(width: 4),
                      Text(e.value, style: TextStyle(fontSize: 12, color: selected ? Theme.of(context).colorScheme.primary : null)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                _board.name = nameCtrl.text.trim().isEmpty ? '我的板块' : nameCtrl.text.trim();
                _board.iconName = iconName;
                _save();
                setState(() {});
                navConfigNotifier.value++; // 底部导航标签文字/图标同步刷新
                Navigator.pop(c);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // 新增 / 编辑条目
  void _editItem({BoardItem? item, int? index}) {
    final isEdit = item != null;
    String type = item?.type ?? 'link';
    final titleCtrl = TextEditingController(text: item?.title ?? '');
    final urlCtrl = TextEditingController(text: item?.url ?? '');
    final bodyCtrl = TextEditingController(text: item?.body ?? '');
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text(isEdit ? '编辑条目' : '新增条目'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'link', label: Text('链接'), icon: Icon(Icons.link, size: 15)),
                ButtonSegment(value: 'note', label: Text('笔记'), icon: Icon(Icons.note, size: 15)),
              ],
              selected: {type},
              onSelectionChanged: (s) => setDlg(() => type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            if (type == 'link')
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: '网址（https://…）', border: OutlineInputBorder(), isDense: true),
              )
            else
              TextField(
                controller: bodyCtrl,
                maxLines: 5,
                minLines: 2,
                decoration: const InputDecoration(labelText: '笔记正文', border: OutlineInputBorder(), isDense: true),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('标题不能为空')));
                  return;
                }
                final newItem = BoardItem(
                  type: type,
                  title: title,
                  url: type == 'link' ? urlCtrl.text.trim() : '',
                  body: type == 'note' ? bodyCtrl.text : '',
                );
                if (isEdit && index != null) {
                  _board.items[index] = newItem;
                } else {
                  _board.items = [..._board.items, newItem];
                }
                _save();
                setState(() {});
                Navigator.pop(c);
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        ),
      ),
    );
  }

  // 删除条目
  void _delItem(int i) {
    final removed = _board.items[i];
    setState(() => _board.items = [..._board.items]..removeAt(i));
    _save();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除条目'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            final l = [..._board.items];
            l.insert(i.clamp(0, l.length), removed);
            _board.items = l;
            _save();
            setState(() {});
          },
        ),
      ),
    );
  }

  // 上下移动条目
  void _move(int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= _board.items.length) return;
    final l = [..._board.items];
    final t = l[i];
    l[i] = l[j];
    l[j] = t;
    _board.items = l;
    _save();
    setState(() {});
  }

  // 点条目：链接跳浏览器；笔记弹窗看正文
  Future<void> _openItem(BoardItem item) async {
    if (item.type == 'link') {
      final url = item.url.trim();
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这条链接没有填网址')));
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网址格式不对')));
        return;
      }
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打不开：${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } else {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(child: Text(item.body.isEmpty ? '（空笔记）' : item.body)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (_missing) {
      return Scaffold(
        appBar: AppBar(title: const Text('板块不存在')),
        body: const Center(child: Text('这个板块已被删除')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_board.name.isEmpty ? '我的板块' : _board.name),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: '板块名称 / 图标', onPressed: _editBoardMeta),
          IconButton(icon: Icon(Icons.delete_outline, color: c.error), tooltip: '删除板块', onPressed: _deleteBoard),
        ],
      ),
      body: _board.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_box_outlined, size: 48, color: c.outline),
                  const SizedBox(height: 12),
                  Text('还没有内容。点下方「新增」加链接或笔记', style: TextStyle(color: c.onSurfaceVariant)),
                ]),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _board.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final it = _board.items[i];
                final isLink = it.type == 'link';
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(isLink ? Icons.link_rounded : Icons.note_rounded, color: c.primary),
                    title: Text(it.title),
                    subtitle: isLink ? (it.url.isEmpty ? const Text('未填网址') : Text(it.url, maxLines: 1, overflow: TextOverflow.ellipsis)) : (it.body.isEmpty ? const Text('空笔记') : Text(it.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    onTap: () => _openItem(it),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.arrow_upward, size: 18), tooltip: '上移', onPressed: i > 0 ? () => _move(i, -1) : null),
                      IconButton(icon: const Icon(Icons.arrow_downward, size: 18), tooltip: '下移', onPressed: i < _board.items.length - 1 ? () => _move(i, 1) : null),
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editItem(item: it, index: i)),
                      IconButton(icon: Icon(Icons.delete_outline, size: 18, color: c.error), onPressed: () => _delItem(i)),
                    ]),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(),
        icon: const Icon(Icons.add),
        label: const Text('新增'),
      ),
    );
  }
}
