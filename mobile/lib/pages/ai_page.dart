// AI 助手页：Agnes / 智谱双提供商，Key 走系统加密存储，流式打字机输出
// 支持「知识库问答」：开启时发送自动查 vault 知识库（kb.dart）+ 内置 Skill 方法库（skilllib.dart）拼上下文
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/core.dart';
import '../services/kb.dart';
import '../services/skilllib.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _atBottom = true;
  final List<_Msg> _msgs = [];
  String _prov = 'agnes';
  String _mode = ''; // AI 学习模式（''=通用，见 Api.aiModes）
  bool _busy = false;
  bool _hasKey = false;
  bool _memOn = true;
  bool _kbOn = true; // 知识库问答开关（设置页也可改 Store.kbOn）
  bool _cancel = false;
  String? _keyError;
  http.Client? _chatClient;

  @override
  void initState() {
    super.initState();
    _prov = Store.aiProv;
    _memOn = Store.aiMemoryOn;
    _kbOn = Store.kbOn;
    _loadKey();
    _input.addListener(_onInput);
    // 恢复上次对话历史（记忆功能）
    for (final m in Store.aiHistory()) {
      _msgs.add(_Msg(m['content'] ?? '', m['role'] == 'user'));
    }
    // 设置页"清空对话历史"时同步清空本页内存
    aiClearGlobal = () {
      if (!mounted) return;
      setState(() => _msgs.clear());
      Store.saveAiHistory([]);
    };
    // 新闻"让 AI 讲讲"：填充输入框（切 tab 由 main 负责）
    aiFillGlobal = (t) {
      if (!mounted) return;
      setState(() => _input.text = t);
    };
    // 记录是否贴底：上滑看历史时，流式输出不强行拽到底
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        _atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 50;
      }
    });
  }

  Future<void> _loadKey() async {
    final k = await Store.aiKey(_prov);
    if (mounted) setState(() => _hasKey = k.isNotEmpty);
  }

  // 输入框文字变化时重建，让"清空"按钮随文字出现/消失
  void _onInput() => setState(() {});

  // 记忆开关：在 AI 页头部一键切换，实时同步到 Store（设置页也读同一个值）
  void _toggleMem() {
    _memOn = !_memOn;
    Store.aiMemoryOn = _memOn;
    setState(() {});
  }

  @override
  void dispose() {
    aiClearGlobal = null;
    aiFillGlobal = null;
    _cancel = true;
    _chatClient?.close();
    _input.removeListener(_onInput);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final current = await Store.aiKey(_prov);
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${_prov == 'agnes' ? 'Agnes' : '智谱'} API Key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'sk- 开头的 Key，加密存本机',
            helperText: current.isNotEmpty ? '已保存（可覆盖）' : '未设置',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await Store.setAiKey(_prov, ctrl.text.trim());
              if (c.mounted) Navigator.pop(c);
              if (mounted) setState(() => _hasKey = ctrl.text.trim().isNotEmpty);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_busy) {
      _stop();
      return;
    }
    final q = _input.text.trim();
    if (q.isEmpty) return;
    final key = await Store.aiKey(_prov);
    if (key.isEmpty) {
      _keyError = '请先点右上角设置 Key';
      setState(() {});
      return;
    }
    _input.clear(); // 先清空输入框（放在 setState 外，避免触发监听里的 setState 嵌套）
    setState(() {
      _busy = true;
      _keyError = null;
      _msgs.add(_Msg(q, true));
      _msgs.add(_Msg('', false, streaming: true)); // 空气泡，流式往里填字
    });
    _scrollToBottom(true);
    await _runStream(q);
  }

  // 发起一次流式对话（不含"加用户气泡/清输入框"，由 _send/_regenerate 负责 UI）
  Future<void> _runStream(String q) async {
    _cancel = false;
    final all = _msgs.where((m) => !m.streaming && !m.isError).map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text}).toList();
    final history = all.sublist(0, all.length - 1);
    final memory = Store.aiMemoryOn ? Store.aiMemoryForChat() : <String>[]; // 只带最近 15 条长期记忆，防 prompt 撑爆
    // 知识库问答：开启时自动查（内置 Skill 方法库离线优先 + vault 知识库云端），无命中/失败静默跳过
    String kb = '';
    if (_kbOn) {
      await SkillLib.ensureLoaded();
      final skillCtx = SkillLib.query(q); // 内置 skill 方法库（离线，无需 token）
      final kbCtx = (await Store.syncToken()).isNotEmpty ? await Kb.query(q) : '';
      kb = [if (skillCtx.isNotEmpty) skillCtx, if (kbCtx.isNotEmpty) kbCtx].join('\n');
    }
    final maxMsgs = Store.aiMemoryMax;
    final ctx = history.length > maxMsgs ? history.sublist(history.length - maxMsgs) : history;
    final key = await Store.aiKey(_prov);

    _chatClient = http.Client();
    try {
      await Api.chatStream(_prov, key, ctx.cast<Map<String, String>>(), q,
          memory: memory,
          kb: kb,
          mode: Api.aiModes[_mode] ?? '',
          client: _chatClient,
          onChunk: (c) {
            if (!mounted || _cancel) return;
            setState(() {
              if (_msgs.isNotEmpty && _msgs.last.streaming) _msgs.last.text += c;
            });
            _scrollToBottom();
          });
      if (!mounted) return;
      setState(() {
        if (_msgs.isNotEmpty) _msgs.last.streaming = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        final cur = _msgs.isNotEmpty && _msgs.last.streaming ? _msgs.last.text : '';
        if (_cancel && cur.trim().isNotEmpty) {
          _msgs.last.streaming = false; // 用户主动停止，保留已生成部分
        } else {
          _msgs.removeLast();
          _msgs.add(_Msg('⚠️ ${_friendly(e)}', false, isError: true));
        }
      });
    } finally {
      _chatClient = null;
    }

    // 记忆开关开着才保存历史（截断到上限，防止无限增长）
    if (Store.aiMemoryOn && mounted) {
      final hist = _msgs.where((m) => !m.streaming && !m.isError).map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text}).toList();
      if (hist.length > maxMsgs) {
        Store.saveAiHistory(hist.sublist(hist.length - maxMsgs));
      } else {
        Store.saveAiHistory(hist);
      }
    }
    _scrollToBottom();
  }

  // 重新生成最后一条 AI 回复（或重试失败的那条）：取最后一条用户消息重发
  Future<void> _regenerate() async {
    if (_busy) return;
    final lastUser = _msgs.lastWhere((m) => m.user, orElse: () => _Msg('', true));
    if (lastUser.text.trim().isEmpty) return;
    // 移除当前的 AI 回复（普通或错误），准备替换
    if (_msgs.isNotEmpty && !_msgs.last.user) {
      _msgs.removeLast();
    }
    setState(() {
      _busy = true;
      _msgs.add(_Msg('', false, streaming: true));
    });
    _scrollToBottom(true);
    await _runStream(lastUser.text);
  }

  // 停止生成：中断流式请求
  void _stop() {
    _cancel = true;
    _chatClient?.close();
  }

  String _friendly(Object e) {
    return e.toString().replaceAll('Exception: ', '').replaceAll('ClientException', '已停止生成');
  }

  void _scrollToBottom([bool force = false]) {
    if (!force && !_atBottom) return; // 用户上滑看历史时不强行拽到底
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      // 顶部：提供商 + Key
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          DropdownButton<String>(
            value: _prov,
            items: Api.aiProviders.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value['label']!))).toList(),
            onChanged: (v) {
              if (v != null) {
                Store.aiProv = v;
                setState(() => _prov = v);
                _loadKey();
              }
            },
          ),
          IconButton(
            icon: Icon(_memOn ? Icons.auto_awesome : Icons.auto_awesome_outlined, size: 20),
            tooltip: _memOn ? 'AI 记忆已开（点此关闭）' : 'AI 记忆已关（点此开启）',
            onPressed: _toggleMem,
          ),
          const Spacer(),
          TextButton.icon(
            icon: Icon(_hasKey ? Icons.key : Icons.key_off, size: 16),
            label: Text(_hasKey ? '已设 Key' : '设置 Key'),
            onPressed: _saveKey,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '清空对话',
            onPressed: _confirmClear,
          ),
        ]),
      ),
      if (_keyError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(_keyError!, style: TextStyle(color: c.error, fontSize: 12)),
        ),
      const Divider(height: 8),
      if (!_hasKey)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            // 警告提示：橙色随主题深浅自动适配（不用硬编码 Colors.orange）
            Icon(Icons.key_off,
                size: 18,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFF0A858)
                    : const Color(0xFFB45309)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('还没设置 API Key，AI 暂时无法回答。点右侧去设置，填好就能用了。',
                  style: TextStyle(fontSize: 13, color: c.onSurface)),
            ),
            TextButton(onPressed: _saveKey, child: const Text('去设置')),
          ]),
        ),
      // 消息区
      Expanded(
        child: _msgs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('输入你的问题，AI 会用大白话回答。\n\nAI 有记忆：聊天会自动记住，下次打开还能接着聊；AI 回答下点「记住」可存为长期记忆。\n\n可问它：总结今天的日报 / 帮我挑值得看的新闻 / 待办怎么安排…',
                      textAlign: TextAlign.center, style: TextStyle(color: c.outline)),
                ),
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _msgs.length,
                itemBuilder: (c, i) => _bubble(_msgs[i]),
              ),
      ),
      // AI 学习模式：通用 / 解题讲解 / 论文润色 / 期末重点 / 作业检查 / 翻译
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ...Api.aiModes.keys.map((m) {
              final sel = _mode == m;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(m.isEmpty ? '💬 通用' : m, style: const TextStyle(fontSize: 12)),
                  selected: sel,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _mode = m),
                ),
              );
            }),
          ]),
        ),
      ),
      // 知识库问答开关：开=发送时自动查 vault 知识库（电脑端 vault-backup 中转）
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() {
                _kbOn = !_kbOn;
                Store.kbOn = _kbOn;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(children: [
                Icon(_kbOn ? Icons.menu_book : Icons.menu_book_outlined,
                    size: 14, color: _kbOn ? c.primary : c.outline),
                const SizedBox(width: 4),
                Text('知识库', style: TextStyle(fontSize: 11, color: _kbOn ? c.primary : c.outline)),
                const SizedBox(width: 4),
                Icon(_kbOn ? Icons.check_circle : Icons.circle_outlined,
                    size: 12, color: _kbOn ? c.primary : c.outline),
              ]),
            ),
          ),
        ]),
      ),
      // 输入区
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '问 AI 点什么…',
                  border: const OutlineInputBorder(),
                  suffixIcon: _input.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: '清空', onPressed: _input.clear)
                      : null,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              tooltip: _busy ? '停止生成' : '发送',
              icon: Icon(_busy ? Icons.stop : Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _bubble(_Msg m) {
    final c = Theme.of(context).colorScheme;
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: m.user ? c.primary : c.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(m.user ? 12 : 4),
            bottomRight: Radius.circular(m.user ? 4 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 流式输出中（或用户/错误）显示纯文本；AI 回复完成后再渲染 markdown，
            // 避免半截 markdown（未闭合 **、# 等）解析出错或闪烁
            if (m.streaming && m.text.isEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('AI 正在思考', style: TextStyle(fontSize: 13, color: c.onSurface.withValues(alpha: 0.6))),
                      const SizedBox(width: 6),
                      TypingDots(color: c.onSurface.withValues(alpha: 0.6)),
              ])
            else if (m.streaming)
              Text('${m.text}▍', style: TextStyle(fontSize: 14, height: 1.5, color: m.user ? c.onPrimary : c.onSurface))
            else if (m.isError)
              Text(m.text, style: TextStyle(fontSize: 14, height: 1.5, color: c.error))
            else if (m.user)
              Text(m.text, style: TextStyle(fontSize: 14, height: 1.5, color: c.onPrimary))
            else
              MarkdownBody(
                data: m.text,
                selectable: true,
                styleSheet: _mdSheet(c),
                onTapLink: (text, href, title) {
                  if (href != null) _openLink(href);
                },
              ),
            // AI 回复操作：记住 / 复制（成功时）/ 重答（成功或失败时）
            if (!m.user && !m.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!m.isError) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _remember(m.text),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.bookmark_add_outlined, size: 13, color: c.primary),
                        const SizedBox(width: 3),
                        Text('记住', style: TextStyle(fontSize: 11, color: c.primary)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _copy(m.text),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.copy_outlined, size: 13, color: c.primary),
                        const SizedBox(width: 3),
                        Text('复制', style: TextStyle(fontSize: 11, color: c.primary)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                  ],
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _regenerate(),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.refresh, size: 13, color: c.primary),
                      const SizedBox(width: 3),
                      Text(m.isError ? '重试' : '重答', style: TextStyle(fontSize: 11, color: c.primary)),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  // markdown 渲染样式：文字色匹配气泡背景（surfaceContainerHighest → onSurface）
  MarkdownStyleSheet _mdSheet(ColorScheme c) => MarkdownStyleSheet(
        p: TextStyle(fontSize: 14, height: 1.5, color: c.onSurface),
        strong: TextStyle(fontWeight: FontWeight.bold, color: c.onSurface),
        em: TextStyle(fontStyle: FontStyle.italic, color: c.onSurface),
        h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.onSurface),
        h2: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.onSurface),
        h3: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.onSurface),
        h4: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.onSurface),
        h5: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.onSurface),
        h6: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.onSurface),
        code: TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: c.surfaceContainerHighest, color: c.onSurface),
        codeblockDecoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
        blockquote: TextStyle(color: c.outline, fontStyle: FontStyle.italic),
        listBullet: TextStyle(color: c.onSurface),
        a: TextStyle(color: c.primary, decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
      );

  void _remember(String text) {
    if (text.trim().isEmpty) return;
    final mem = Store.aiMemory();
    if (!mem.contains(text)) {
      mem.add(text);
      Store.saveAiMemory(mem);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📌 已记住这条，可在"设置 → AI 记忆"里查看/删除')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这条已经记住了')));
    }
  }

  void _copy(String text) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制回复')));
  }

  // 打开 AI 回复里的链接（markdown 链接点击）
  Future<void> _openLink(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打不开链接：$url')));
    }
  }

  // 清空对话：带二次确认，避免误触
  Future<void> _confirmClear() async {
    if (_msgs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定要清空当前对话吗？已保存的长期记忆不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _msgs.clear());
      Store.saveAiHistory([]);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话已清空')));
    }
  }
}

class _Msg {
  String text;
  final bool user;
  final bool isError;
  bool streaming;
  _Msg(this.text, this.user, {this.isError = false, this.streaming = false});
}

// AI 流式刚开始（还没收到第一个字）时的三点跳动"正在思考"指示器
class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, required this.color});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = (_c.value + i / 3) % 1;
            final offset = -4 * (1 - (2 * t - 1).abs()); // 上下弹跳，错峰
            return Transform.translate(
              offset: Offset(0, offset),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            );
          },
        );
      }),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}
