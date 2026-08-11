// AI 助手页：Agnes / 智谱双提供商，Key 走系统加密存储，流式打字机输出
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/core.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  String _prov = 'agnes';
  bool _busy = false;
  bool _hasKey = false;
  bool _cancel = false;
  String? _keyError;
  http.Client? _chatClient;

  @override
  void initState() {
    super.initState();
    _prov = Store.aiProv;
    _loadKey();
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
  }

  Future<void> _loadKey() async {
    final k = await Store.aiKey(_prov);
    if (mounted) setState(() => _hasKey = k.isNotEmpty);
  }

  @override
  void dispose() {
    aiClearGlobal = null;
    aiFillGlobal = null;
    _cancel = true;
    _chatClient?.close();
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
    setState(() {
      _busy = true;
      _keyError = null;
      _msgs.add(_Msg(q, true));
      _msgs.add(_Msg('', false, streaming: true)); // 空气泡，流式往里填字
      _input.clear();
    });
    _scrollToBottom();
    _cancel = false;

    final all = _msgs.where((m) => !m.streaming && !m.isError).map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text}).toList();
    final history = all.sublist(0, all.length - 1);
    final memory = Store.aiMemoryOn ? Store.aiMemory() : <String>[];
    final maxMsgs = Store.aiMemoryMax;
    final ctx = history.length > maxMsgs ? history.sublist(history.length - maxMsgs) : history;

    _chatClient = http.Client();
    try {
      await Api.chatStream(_prov, key, ctx.cast<Map<String, String>>(), q,
          memory: memory,
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

  // 停止生成：中断流式请求
  void _stop() {
    _cancel = true;
    _chatClient?.close();
  }

  String _friendly(Object e) {
    return e.toString().replaceAll('Exception: ', '').replaceAll('ClientException', '已停止生成');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
          const Spacer(),
          TextButton.icon(
            icon: Icon(_hasKey ? Icons.vpn_key : Icons.vpn_key_off, size: 16),
            label: Text(_hasKey ? '已设 Key' : '设置 Key'),
            onPressed: _saveKey,
          ),
        ]),
      ),
      if (_keyError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(_keyError!, style: TextStyle(color: c.error, fontSize: 12)),
        ),
      const Divider(height: 8),
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
                decoration: const InputDecoration(hintText: '问 AI 点什么…', border: OutlineInputBorder()),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _send,
              child: Text(_busy ? '■ 停止' : '➤ 发送'),
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
            Text(
              m.streaming && m.text.isEmpty ? '…' : (m.streaming ? '${m.text}▍' : m.text),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: m.user ? c.onPrimary : (m.isError ? c.error : c.onSurface),
              ),
            ),
            // AI 回复可"记住"（存长期记忆）
            if (!m.user && !m.isError && !m.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _remember(m.text),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bookmark_add_outlined, size: 13, color: c.primary),
                    const SizedBox(width: 3),
                    Text('记住', style: TextStyle(fontSize: 11, color: c.primary)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
}

class _Msg {
  String text;
  final bool user;
  final bool isError;
  bool streaming;
  _Msg(this.text, this.user, {this.isError = false, this.streaming = false});
}
