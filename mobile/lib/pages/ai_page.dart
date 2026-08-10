// AI 助手页：Agnes / 智谱双提供商，Key 存本地
import 'package:flutter/material.dart';
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
  String? _keyError;

  @override
  void initState() {
    super.initState();
    _prov = Store.aiProv;
  }

  void _saveKey() {
    final ctrl = TextEditingController(text: Store.aiKey(_prov));
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${_prov == 'agnes' ? 'Agnes' : '智谱'} API Key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'sk- 开头的 Key，仅存本机',
            helperText: Store.aiKey(_prov).isNotEmpty ? '已保存（可覆盖）' : '未设置',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Store.setAiKey(_prov, ctrl.text.trim());
              Navigator.pop(c);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy) return;
    final key = Store.aiKey(_prov);
    if (key.isEmpty) {
      _keyError = '请先点右上角设置 Key';
      setState(() {});
      return;
    }
    setState(() {
      _busy = true;
      _keyError = null;
      _msgs.add(_Msg(q, true));
      _msgs.add(_Msg('…思考中', false, thinking: true));
      _input.clear();
    });
    _scrollToBottom();
    try {
      final history = _msgs.where((m) => !m.thinking).map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text}).toList()..removeLast();
      final ans = await Api.chat(_prov, key, history.cast<Map<String, String>>(), q);
      if (!mounted) return;
      setState(() {
        _msgs.removeLast();
        _msgs.add(_Msg(ans, false));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.removeLast();
        _msgs.add(_Msg('⚠️ ${e.toString().replaceAll('Exception: ', '')}', false, isError: true));
        _busy = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _ask(String text) {
    _input.text = text;
    _send();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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
              }
            },
          ),
          const Spacer(),
          TextButton.icon(
            icon: Icon(Store.aiKey(_prov).isNotEmpty ? Icons.vpn_key : Icons.vpn_key_off, size: 16),
            label: Text(Store.aiKey(_prov).isNotEmpty ? '已设 Key' : '设置 Key'),
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
                  child: Text('输入你的问题，AI 会用大白话回答。\n\n可问它：总结今天的日报 / 帮我挑值得看的新闻 / 待办怎么安排…',
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
            FilledButton(onPressed: _send, child: const Text('➤ 发送')),
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
        child: Text(
          m.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: m.user ? c.onPrimary : (m.isError ? c.error : c.onSurface),
            fontStyle: m.thinking ? FontStyle.italic : null,
          ),
        ),
      ),
    );
  }
}

class _Msg {
  final String text;
  final bool user;
  final bool thinking;
  final bool isError;
  _Msg(this.text, this.user, {this.thinking = false, this.isError = false});
}
