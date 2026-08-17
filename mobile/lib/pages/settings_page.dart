// 设置页：AI 助手记忆管理（开关/条数/长期记忆/清空历史）+ 外观 + 云同步 + 知识库
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../services/core.dart';
import '../services/sync.dart';
import '../services/kb.dart';
import '../boards.dart';
import '../nav_notifier.dart';
import 'custom_board_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _memOn = true;
  int _memMax = 20;
  int _memCount = 0;
  bool _ctxOn = true; // 情境感知：AI 发送时自动带入今日课程/待办/倒计时/心情
  bool _autoMemOn = false; // 记忆自动抽取：对话结束自动提炼关键事实存长期记忆
  final _repoCtrl = TextEditingController(); // 云同步仓库
  final _tokenCtrl = TextEditingController(); // GitHub Token（加密存储）
  final _kbRepoCtrl = TextEditingController(); // 知识库仓库
  final _kbBranchCtrl = TextEditingController(); // 知识库分支
  bool _kbOn = true; // 知识库问答开关
  bool _autoSync = false; // 启动时自动备份
  bool _busy = false; // 云同步/知识库操作进行中，禁用按钮防误触
  List<String> _navCfg = Store.builtInBoardIds.toList(); // 底部导航 7 个板块 ID
  List<CustomBoard> _boards = []; // 自定义板块列表

  @override
  void initState() {
    super.initState();
    _refresh();
    _repoCtrl.text = Store.syncRepo;
    _kbRepoCtrl.text = Store.kbRepo;
    _kbBranchCtrl.text = Store.kbBranch;
    _kbOn = Store.kbOn;
    _autoSync = Store.autoSync;
    Store.syncToken().then((t) {
      if (mounted && t.isNotEmpty) _tokenCtrl.text = t;
    });
  }

  @override
  void dispose() {
    _repoCtrl.dispose();
    _tokenCtrl.dispose();
    _kbRepoCtrl.dispose();
    _kbBranchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    _memOn = Store.aiMemoryOn;
    _memMax = Store.aiMemoryMax;
    _memCount = Store.aiMemory().length;
    _ctxOn = Store.aiContextOn;
    _autoMemOn = Store.aiAutoMemOn;
    // 用 buildBoards 收敛成恰好 7 个有效板块，自动剔除脏 ID，避免导航错乱
    _navCfg = buildBoards(Store.navConfig).map((b) => b.id).toList();
    if (_navCfg.join(',') != Store.navConfig.join(',')) Store.navConfig = _navCfg; // 存量脏数据顺手修复
    _boards = Store.customBoards();
  }

  void _reload() => setState(_refresh);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      // ---------- AI 记忆 ----------
      _sectionTitle('AI 助手记忆', icon: Icons.psychology_rounded),
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
          SwitchListTile(
            title: const Text('情境感知'),
            subtitle: const Text('AI 发送时自动带入你今天的课程 / 待办 / 倒计时 / 心情，给更贴合的建议'),
            value: _ctxOn,
            onChanged: (v) {
              Store.aiContextOn = v;
              _reload();
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('记忆自动抽取'),
            subtitle: const Text('对话结束后自动提炼关键事实存进长期记忆（默认关，防止 AI 乱记）'),
            value: _autoMemOn,
            onChanged: (v) {
              Store.aiAutoMemOn = v;
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
      _sectionTitle('外观', icon: Icons.palette_rounded),
      Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.dark_mode_outlined),
              title: Text('外观'),
              subtitle: Text('选择浅色 / 深色，或跟随系统自动切换'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 'system', label: Text('系统'), icon: Icon(Icons.brightness_auto, size: 15)),
                        ButtonSegment(value: 'dark', label: Text('深色'), icon: Icon(Icons.dark_mode, size: 15)),
                        ButtonSegment(value: 'light', label: Text('浅色'), icon: Icon(Icons.light_mode, size: 15)),
                      ],
                      selected: {themeModeNotifier.value},
                      onSelectionChanged: (s) => themeModeNotifier.value = s.first,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ---------- 板块管理（底部导航 7 槽位可排序/替换 + 自定义板块） ----------
      _sectionTitle('板块管理', icon: Icons.view_agenda_rounded),
      Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('底部导航固定 7 个位置，可拖动排序、替换成内置板块，或放你自建的板块。', style: TextStyle(fontSize: 12)),
          ),
          ...List.generate(7, (i) => _navSlot(i)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _newBoard,
              icon: const Icon(Icons.add),
              label: const Text('新建自定义板块'),
            ),
          ),
          if (_boards.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text('已建板块', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
            ),
            ..._boards.map((b) => _customBoardRow(b)),
          ],
        ]),
      ),

      // ---------- 数据备份 ----------
      _sectionTitle('数据备份', icon: Icons.archive_rounded),
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

      // ---------- 云同步（GitHub 中转，换机/多设备不丢数据） ----------
      _sectionTitle('云同步', icon: Icons.cloud_sync_rounded),
      Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _repoCtrl,
              onChanged: (v) => Store.syncRepo = v, // 实时持久化，避免只在按钮里存
              decoration: const InputDecoration(labelText: 'GitHub 仓库', hintText: '用户名/仓库名，如 W-lik721/personal-workbench', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: TextField(
              controller: _tokenCtrl,
              obscureText: true,
              onChanged: (v) { if (v.trim().isNotEmpty) Store.setSyncToken(v.trim()); }, // 实时持久化
              decoration: const InputDecoration(labelText: 'GitHub Token（访问令牌）', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text('Token 在 GitHub「设置 → Developer settings → Personal access tokens」生成，勾 repo 权限。只加密存手机本地。', style: TextStyle(fontSize: 11, color: c.outline, height: 1.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(children: [
              Expanded(child: FilledButton.tonal(onPressed: _busy ? null : _syncUpload, child: const Text('上传备份'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: _busy ? null : _syncDownload, child: const Text('下载恢复'))),
            ]),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.backup_outlined, size: 20),
            title: const Text('启动时自动备份', style: TextStyle(fontSize: 13)),
            subtitle: const Text('每次打开 App 自动把数据备份到 GitHub（需已配 Token）', style: TextStyle(fontSize: 11)),
            trailing: Switch(value: _autoSync, onChanged: (v) { setState(() { _autoSync = v; Store.autoSync = v; }); }),
          ),
        ]),
      ),

      // ---------- 知识库（vault 中转，复用云同步 token） ----------
      _sectionTitle('知识库', icon: Icons.menu_book_rounded),
      Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _kbRepoCtrl,
              onChanged: (v) => Store.kbRepo = v, // 实时持久化，去掉方法内 isEmpty 兜底
              decoration: const InputDecoration(labelText: '知识库仓库', hintText: 'W-lik721/vault-backup', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: TextField(
              controller: _kbBranchCtrl,
              onChanged: (v) => Store.kbBranch = v, // 实时持久化
              decoration: const InputDecoration(labelText: '分支（默认 main）', hintText: 'main', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.menu_book_outlined, size: 20),
            title: const Text('AI 问答时自动查知识库', style: TextStyle(fontSize: 13)),
            trailing: Switch(value: _kbOn, onChanged: (v) { setState(() { _kbOn = v; Store.kbOn = v; }); }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text('AI 助手发送时自动匹配电脑知识库（vault）相关笔记作为参考。仓库填你 vault 的 GitHub 镜像，token 复用上面的云同步。', style: TextStyle(fontSize: 11, color: c.outline, height: 1.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(children: [
              Expanded(child: FilledButton.tonal(onPressed: _busy ? null : _kbUpload, child: const Text('记忆入库'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: _busy ? null : _kbIndex, child: const Text('测试索引'))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _kbNotes,
                icon: const Icon(Icons.note_alt_outlined, size: 18),
                label: const Text('速记入库（今天的速记存进知识库）'),
              ),
            ),
          ),
        ]),
      ),

      // ---------- 危险操作 ----------
      _sectionTitle('危险操作', icon: Icons.dangerous_rounded),
      Card(
        child: ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: c.error),
          title: Text('清空所有数据', style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
          subtitle: const Text('删除待办/速记/收藏/课程表/AI 历史与记忆（保留 API Key 和主题设置）'),
          onTap: _confirmResetAll,
        ),
      ),

      // ---------- 关于 ----------
      _sectionTitle('关于', icon: Icons.info_rounded),
      const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('个人工作台'),
          subtitle: Text('v$appVersion · 数据全部存手机本地，不上传\n日报/新闻来自公开接口，需联网'),
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _sectionTitle(String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        ]),
      );

  // 单个导航槽位：显示当前板块 + 下拉替换 + 上下排序（自定义板块可进入编辑）
  Widget _navSlot(int i) {
    final c = Theme.of(context).colorScheme;
    final curId = _navCfg[i];
    final meta = resolveBoard(curId);
    final usedElsewhere = _navCfg.where((id) => id != curId).toSet();
    // 可选项：未在其他槽位使用的内置板块 + 未在其他槽位使用的自定义板块 + 当前项本身
    final pool = <String>[];
    for (final id in kBuiltInIds) {
      if (id == curId || !usedElsewhere.contains(id)) pool.add(id);
    }
    for (final b in _boards) {
      if (b.id == curId || !usedElsewhere.contains(b.id)) pool.add(b.id);
    }
    final isCustom = !kBuiltInIds.contains(curId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        SizedBox(width: 18, child: Text('${i + 1}', style: TextStyle(color: c.outline, fontSize: 13))),
        IconTheme(data: const IconThemeData(size: 20), child: meta.icon),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: curId,
            isExpanded: true,
            underline: const SizedBox(),
            items: pool.map((id) {
              final m = resolveBoard(id);
              return DropdownMenuItem(
                value: id,
                child: Row(children: [
                  IconTheme(data: const IconThemeData(size: 18), child: m.icon),
                  const SizedBox(width: 8),
                  Text(m.label),
                ]),
              );
            }).toList(),
            onChanged: (v) {
              if (v == null || v == curId) return;
              setState(() {
                _navCfg[i] = v;
                Store.navConfig = _navCfg;
                navConfigNotifier.value++;
              });
            },
          ),
        ),
        if (i > 0) IconButton(icon: const Icon(Icons.arrow_upward, size: 18), tooltip: '上移', onPressed: () => _moveSlot(i, -1)),
        if (i < 6) IconButton(icon: const Icon(Icons.arrow_downward, size: 18), tooltip: '下移', onPressed: () => _moveSlot(i, 1)),
        if (isCustom) IconButton(icon: const Icon(Icons.open_in_new, size: 18), tooltip: '编辑板块内容', onPressed: () => _openBoard(curId)),
      ]),
    );
  }

  void _moveSlot(int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= 7) return;
    setState(() {
      final t = _navCfg[i];
      _navCfg[i] = _navCfg[j];
      _navCfg[j] = t;
      Store.navConfig = _navCfg;
      navConfigNotifier.value++;
    });
  }

  // 已建板块的一行：显示名称/条数/是否在导航，可进入编辑或删除（删除会同步修复导航）
  Widget _customBoardRow(CustomBoard b) {
    final c = Theme.of(context).colorScheme;
    final idx = _navCfg.indexOf(b.id);
    return ListTile(
      leading: Icon(customIcon(b.iconName)),
      title: Text(b.name.isEmpty ? '我的板块' : b.name),
      subtitle: Text('${b.items.length} 条${idx >= 0 ? ' · 已在导航第 ${idx + 1} 位' : ' · 未在导航'}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.open_in_new, size: 18), tooltip: '编辑', onPressed: () => _openBoard(b.id)),
        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: c.error), tooltip: '删除板块', onPressed: () => _deleteBoard(b.id)),
      ]),
    );
  }

  void _openBoard(String id) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomBoardPage(boardId: id))).then((_) {
      // 板块名/图标可能被改 → 刷新导航标签；列表也可能变
      setState(() {
        _navCfg = Store.navConfig;
        _boards = Store.customBoards();
      });
      navConfigNotifier.value++;
    });
  }

  // 新建自定义板块：直接打开编辑页，建好后再去任意槽位下拉里选它
  void _newBoard() {
    final id = 'cb_${DateTime.now().millisecondsSinceEpoch}';
    final nb = CustomBoard(id: id, name: '我的板块', iconName: 'star', items: const []);
    Store.saveCustomBoards([...Store.customBoards(), nb]);
    setState(() => _boards = Store.customBoards());
    _openBoard(id);
  }

  // 删除自定义板块：同步把导航里引用它的位置换成未使用的内置板块，保证仍是 7 个
  Future<void> _deleteBoard(String id) async {
    final c = Theme.of(context).colorScheme;
    final b = _boards.where((x) => x.id == id).firstOrNull;
    final name = b?.name.isEmpty == true ? '我的板块' : (b?.name ?? '这个板块');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('删除板块？'),
        content: Text('会删掉「$name」及里面的内容，并从底部导航移除。此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Store.saveCustomBoards(Store.customBoards().where((x) => x.id != id).toList());
    // 导航自愈
    final nav = Store.navConfig;
    final keep = nav.where((x) => x != id && boardExists(x)).toSet();
    final healed = <String>[];
    for (final x in nav) {
      if (x == id || !boardExists(x)) {
        final unused = kBuiltInIds.firstWhere((b2) => !keep.contains(b2) && !healed.contains(b2), orElse: () => 'home');
        healed.add(unused);
        keep.add(unused);
      } else {
        healed.add(x);
      }
    }
    Store.navConfig = healed;
    navConfigNotifier.value++;
    setState(() {
      _navCfg = Store.navConfig;
      _boards = Store.customBoards();
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除板块')));
  }

  // 仓库名校验：owner/repo，禁止多余斜杠、空段、尾斜杠
  bool _validRepo(String repo) => RegExp(r'^\w[\w.-]*/\w[\w.-]*$').hasMatch(repo.trim());

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
              if (_memMax == n) Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
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
                  child: Text('清空全部', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话历史已清空')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出备份：$fileName')));
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已从备份恢复数据')));
  }

  // 云同步：上传备份（本地数据 → GitHub 仓库 app-data.json）
  Future<void> _syncUpload() async {
    if (_busy) return;
    final token = _tokenCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    if (!_validRepo(repo)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('仓库格式应为：用户名/仓库名（如 W-lik721/personal-workbench）')));
      return;
    }
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填好 GitHub Token（在云同步栏）')));
      return;
    }
    Store.syncRepo = repo;
    await Store.setSyncToken(token);
    if (!mounted) return;
    setState(() => _busy = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上传…')));
    try {
      await Sync.upload(token, repo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已上传备份到 $repo')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 云同步：下载恢复（GitHub → 本地，会覆盖当前数据，需二次确认）
  Future<void> _syncDownload() async {
    if (_busy) return;
    final token = _tokenCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    if (!_validRepo(repo)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('仓库格式应为：用户名/仓库名（如 W-lik721/personal-workbench）')));
      return;
    }
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填好 GitHub Token（在云同步栏）')));
      return;
    }
    Store.syncRepo = repo;
    await Store.setSyncToken(token); // 持久化，避免进程重建后丢失
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('从云端恢复？'),
        content: const Text('会用云端备份覆盖当前手机的待办/速记/收藏/课程表等数据。确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在下载…')));
    try {
      final m = await Sync.download(token, repo);
      Store.importAll(m);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已从云端恢复（$repo）')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 知识库通用鉴权包装：校验 token / 仓库格式，统一 loading 态与错误提示
  // fn(token, repo) 为实际操作；onBusy 用于在操作期间禁用按钮
  Future<void> _withKbAuth(Future<void> Function(String token, String repo) fn, String doing) async {
    if (_busy) return;
    final token = _tokenCtrl.text.trim();
    final repo = Store.kbRepo; // 已通过 onChanged 实时持久化，不再就地兜底默认仓库
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先在「云同步」填好 GitHub Token（复用同一个）')));
      return;
    }
    if (!_validRepo(repo)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('知识库仓库格式应为：用户名/仓库名（左侧「知识库」栏）')));
      return;
    }
    setState(() => _busy = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doing)));
    try {
      await fn(token, repo);
      if (!mounted) return;
      // 各 fn 内已弹成功 SnackBar；这里仅结束 loading
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 知识库：记忆入库（AI 长期记忆 → vault 05-数字分身/App记忆/）
  Future<void> _kbUpload() => _withKbAuth((token, repo) async {
        await Kb.uploadMemory(token, repo);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('记忆已入库：$repo 的 05-数字分身/App记忆/')));
      }, '正在上传记忆到知识库…');

  // 知识库：速记入库（今天的速记 → vault 05-数字分身/App速记/）
  Future<void> _kbNotes() => _withKbAuth((token, repo) async {
        await Kb.uploadNotes(token, repo);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('速记已入库：$repo 的 05-数字分身/App速记/')));
      }, '正在上传速记到知识库…');

  // 知识库：测试索引连通（拉 kb-index.json 看条数）
  Future<void> _kbIndex() => _withKbAuth((token, repo) async {
        final idx = await Kb.index(token, repo, Store.kbBranch);
        if (!mounted) return;
        if (idx.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('索引拉取失败：仓库里没有 kb-index.json（电脑端需先运行 gen_kb_index.py）')));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('知识库连通：索引 ${idx.length} 篇笔记，AI 问答可用')));
      }, '正在测试知识库索引…');

  // 清空所有数据：两次确认 + 输入"清空"验证，防止误触
  Future<void> _confirmResetAll() async {
    final step1 = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空所有数据？'),
        content: const Text('这会删除：\n· 待办清单\n· 我的速记\n· 我的收藏\n· 常用入口\n· 课程表\n· AI 对话历史与长期记忆\n\n不会删除：API Key、主题设置。\n\n此操作不可撤销！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;
    final ctrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('最后确认'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('请输入「清空」两个字来确认：'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '清空'),
              onChanged: (_) => setDlg(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: ctrl.text.trim() == '清空' ? () => Navigator.pop(c, true) : null,
              child: const Text('确认清空'),
            ),
          ],
        ),
      ),
    );
    if (step2 != true || !mounted) return;
    Store.resetAllData();
    aiClearGlobal?.call(); // 通知 AI 页清空内存中的对话
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空所有数据')));
  }
}
