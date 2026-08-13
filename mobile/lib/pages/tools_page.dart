// 工具箱：账号保管箱（加密存储）+ 心情日记（AI 周报）+ 拍照识题（OCR → AI）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/core.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  int _seg = 0; // 0 账号 / 1 心情 / 2 识题

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔧 工具箱')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<int>(
            selected: {_seg},
            onSelectionChanged: (s) => setState(() => _seg = s.first),
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.lock_outline, size: 18), label: Text('账号')),
              ButtonSegment(value: 1, icon: Icon(Icons.mood, size: 18), label: Text('心情')),
              ButtonSegment(value: 2, icon: Icon(Icons.camera_alt_outlined, size: 18), label: Text('识题')),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _seg,
            children: const [
              _AccountTab(),
              _MoodTab(),
              _OcrTab(),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============ ① 账号保管箱（加密存储 Keystore/Keychain，不落明文） ============
class _AccountTab extends StatefulWidget {
  const _AccountTab();
  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  List<Account> _list = [];
  bool _busy = true;
  bool _showPw = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await Store.accounts();
    if (mounted) setState(() => _list = l..sort((a, b) => a.title.compareTo(b.title)));
    if (mounted) setState(() => _busy = false);
  }

  void _add([Account? a, int? idx]) async {
    final titleCtrl = TextEditingController(text: a?.title ?? '');
    final userCtrl = TextEditingController(text: a?.username ?? '');
    final pwCtrl = TextEditingController(text: a?.password ?? '');
    final noteCtrl = TextEditingController(text: a?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(a == null ? '添加账号' : '编辑账号'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleCtrl, autofocus: true, decoration: const InputDecoration(labelText: '平台 / 站点', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: '账号 / 手机号', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: pwCtrl, obscureText: true, decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '备注（可选）', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(c, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final acc = Account(
      titleCtrl.text.trim(),
      username: userCtrl.text.trim(),
      password: pwCtrl.text,
      note: noteCtrl.text.trim(),
    );
    final l = await Store.accounts();
    if (idx == null) {
      l.add(acc);
    } else {
      l[idx] = acc;
    }
    await Store.saveAccounts(l);
    _reload();
  }

  Future<void> _del(int i) async {
    HapticFeedback.mediumImpact();
    final l = await Store.accounts();
    final name = l[i].title;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除账号？'),
        content: Text('确定删除「$name」吗？此操作不可撤销。'),
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
    if (ok != true) return;
    l.removeAt(i);
    await Store.saveAccounts(l);
    _reload();
  }

  void _copy(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制$label')));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Stack(children: [
      _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                color: c.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.shield_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('密码加密存于手机系统保险库（Keystore/Keychain），不落明文、不上云。',
                          style: TextStyle(fontSize: 12, color: c.onTertiaryContainer)),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _showPw = !_showPw),
                      icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility, size: 16),
                      label: Text(_showPw ? '隐藏' : '显示', style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              ..._list.asMap().entries.map((e) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(e.value.title),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (e.value.username.isNotEmpty) Text(e.value.username, style: const TextStyle(fontSize: 12)),
                        if (e.value.password.isNotEmpty)
                          Text(_showPw ? e.value.password : '•' * e.value.password.length.clamp(4, 12),
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                        if (e.value.note.isNotEmpty) Text(e.value.note, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (e.value.username.isNotEmpty)
                          IconButton(icon: const Icon(Icons.person_outline, size: 18), tooltip: '复制账号', onPressed: () => _copy(e.value.username, '账号')),
                        if (e.value.password.isNotEmpty)
                          IconButton(icon: const Icon(Icons.copy_outlined, size: 18), tooltip: '复制密码', onPressed: () => _copy(e.value.password, '密码')),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18), tooltip: '编辑', onPressed: () => _add(e.value, e.key)),
                        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: c.error), tooltip: '删除', onPressed: () => _del(e.key)),
                      ]),
                    ),
                  )),
              if (_list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text('还没有保存任何账号。点右下角 + 把常用平台的账号密码收进来，全部加密保存在本机。', style: TextStyle(color: c.outline)),
                ),
              const SizedBox(height: 70),
            ]),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton(onPressed: () => _add(), tooltip: '添加账号', child: const Icon(Icons.add)),
      ),
    ]);
  }
}

// ============ ② 心情日记 + AI 周报 ============
class _MoodTab extends StatefulWidget {
  const _MoodTab();
  @override
  State<_MoodTab> createState() => _MoodTabState();
}

class _MoodTabState extends State<_MoodTab> {
  List<Mood> _list = [];
  final _ctrl = TextEditingController();
  String _emoji = '🙂';
  static const _emojis = ['😊', '🙂', '😍', '🤔', '😴', '🥳', '😎', '💪', '😰', '😢', '😡', '🙃'];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _list = Store.moods()..sort((a, b) => b.at.compareTo(a.at)));

  // 今天（YYYY-MM-DD）已有的心情，若有则编辑它
  Mood? _todayMood() {
    final now = DateTime.now();
    final ds = '${now.year}-${now.month}-${now.day}';
    for (final m in _list) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.at);
      if ('${d.year}-${d.month}-${d.day}' == ds) return m;
    }
    return null;
  }

  void _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写点今天的心情吧')));
      return;
    }
    final l = Store.moods();
    final existing = _todayMood();
    if (existing != null) {
      final idx = l.indexWhere((m) => m.at == existing.at);
      if (idx >= 0) l[idx] = Mood(text, _emoji, existing.at);
    } else {
      l.add(Mood(text, _emoji, DateTime.now().millisecondsSinceEpoch));
    }
    Store.saveMoods(l);
    _ctrl.clear();
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已记下今天的心情')));
  }

  void _del(int i) {
    HapticFeedback.mediumImpact();
    final l = Store.moods();
    l.removeAt(i);
    Store.saveMoods(l);
    _reload();
  }

  // 生成「本周心情周报」并交给 AI：取最近 7 天的心情，拼成提示词
  void _weeklyReport() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final week = Store.moods().where((m) => m.at >= now - 7 * 86400000).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (week.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这周还没写心情日记，先记几条吧')));
      return;
    }
    final lines = week.map((m) {
      final d = DateTime.fromMillisecondsSinceEpoch(m.at);
      return '· ${d.month}/${d.day} ${m.emoji} ${m.text}';
    }).join('\n');
    final prompt = '下面是用户最近 7 天的心情日记（日期 + 心情 emoji + 文字）：\n$lines\n\n'
        '请生成一份「本周心情周报」：用温柔、像朋友聊天的语气，总结这周的情绪趋势，'
        '点出高光时刻和低谷，最后给一句贴心的鼓励或建议。不要冷冰冰的列表，要有人味。';
    if (aiAskGlobal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 助手尚未就绪')));
      return;
    }
    aiAskGlobal!(prompt, send: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = _todayMood();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t != null ? '今天的心情（点保存可更新）' : '记下今天的心情', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: _emojis.map((e) => ChoiceChip(
                label: Text(e, style: const TextStyle(fontSize: 18)),
                selected: _emoji == e,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _emoji = e),
              )).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '今天过得怎么样？一句话就好…',
                border: const OutlineInputBorder(),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _ctrl.clear())
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存今天的心情'),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _weeklyReport,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('📊 AI 生成本周周报'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text('历史', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c.primary)),
      ),
      ..._list.asMap().entries.map((e) {
        final m = e.value;
        final d = DateTime.fromMillisecondsSinceEpoch(m.at);
        return Dismissible(
          key: ObjectKey(m.at),
          direction: DismissDirection.endToStart,
          background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: c.error, child: const Icon(Icons.delete_outline, color: Colors.white)),
          onDismissed: (_) => _del(e.key),
          child: Card(
            child: ListTile(
              leading: Text(m.emoji, style: const TextStyle(fontSize: 26)),
              title: Text(m.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
              onTap: () {
                setState(() {
                  _ctrl.text = m.text;
                  _emoji = m.emoji;
                });
                Scrollable.ensureVisible(context);
              },
            ),
          ),
        );
      }),
      if (_list.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('还没有历史心情。每天记一句，周末让 AI 帮你写周报。', style: TextStyle(color: c.outline))),
      const SizedBox(height: 16),
    ]);
  }
}

// ============ ③ 拍照识题（OCR 提取文字 → 交给 AI 解题讲解） ============
class _OcrTab extends StatefulWidget {
  const _OcrTab();
  @override
  State<_OcrTab> createState() => _OcrTabState();
}

class _OcrTabState extends State<_OcrTab> {
  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 90);
    if (image == null) return;
    setState(() { _busy = true; _err = null; });
    String text = '';
    try {
      // 指定中文识别模型（Google ML Kit 默认只含拉丁字母，中文需单独加载模型）
      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final input = InputImage.fromFilePath(image.path);
      final recognized = await recognizer.processImage(input);
      text = recognized.text.trim();
      await recognizer.close();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = '识别失败：${e.toString().replaceFirst('Exception: ', '')}'; });
      return;
    }
    if (!mounted) return;
    setState(() {
      _textCtrl.text = text;
      _busy = false;
      _err = text.isEmpty ? '没识别出文字，换个角度或手写更清楚的照片试试' : null;
    });
    if (text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已识别文字，可编辑后发给 AI 讲解')));
    }
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先识别或输入题目文字')));
      return;
    }
    if (aiAskGlobal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 助手尚未就绪')));
      return;
    }
    // 用「解题讲解」模式把题目交给 AI（先讲思路再给答案）
    aiAskGlobal!(text, mode: '📚 解题讲解', send: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        color: c.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            const Icon(Icons.camera_alt_outlined, size: 32),
            const SizedBox(height: 8),
            const Text('拍下或选一张题目照片', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('App 在手机本地用 OCR 把图里的文字提取出来（不上传图片），再交给 AI 用「解题讲解」模式讲给你听。',
                style: TextStyle(fontSize: 12, color: c.onSecondaryContainer), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.camera_alt, size: 18), label: const Text('拍照'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('相册'))),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_busy)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('正在识别图片中的文字…', style: TextStyle(fontSize: 12))]))),
      if (_err != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_err!, style: TextStyle(color: c.error, fontSize: 13)),
        ),
      if (!_busy && _textCtrl.text.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 4),
          child: Text('识别出的文字（可编辑）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        TextField(
          controller: _textCtrl,
          maxLines: 8,
          minLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '识别出的题目文字会出现在这里，可手动修改'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: const Text('📚 发给 AI 解题讲解'),
          ),
        ),
      ],
      if (!_busy && _textCtrl.text.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('拍完照或选好图后，识别出的文字会显示在这里，确认无误再点「发给 AI 解题讲解」。', style: TextStyle(color: c.outline, fontSize: 12)),
        ),
      const SizedBox(height: 16),
    ]);
  }
}
