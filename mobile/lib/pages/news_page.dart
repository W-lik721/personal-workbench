// 新闻页：AI 日报 + 每日新闻（TabBar 切换，本地缓存优先，Tab 懒加载）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/core.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  DailyReport? _report;
  DailyNews? _dnews;
  List<V2exItem>? _hot;
  String? _errReport;
  String? _errDnews;
  String? _errHot;
  bool _loadingReport = true;
  bool _loadingDnews = false;
  bool _loadingHot = false;
  bool _staleReport = false; // 当前日报来自缓存
  bool _staleDnews = false;
  bool _staleHot = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // 懒加载：切到"每日新闻"才首次请求（技术热榜在 initState 里已预拉，保证速览卡完整）
    _tab.addListener(() {
      if (_tab.index == 1 && _dnews == null && !_loadingDnews) _loadDnews();
    });
    _loadReport();
    _loadHot();
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!silent) setState(() { _loadingReport = true; _errReport = null; });
    // 有缓存且还没显示 → 先显示缓存，避免白屏
    final cj = Store.cacheReportJson;
    if (cj != null && _report == null) {
      try {
        final r = Api.parseDailyReport(cj);
        if (mounted) setState(() { _report = r; _loadingReport = false; _staleReport = true; });
      } catch (_) {}
    }
    try {
      final body = await Api.fetchDailyReportBody();
      Store.cacheReportJson = body;
      Store.cacheReportAt = DateTime.now().millisecondsSinceEpoch;
      if (mounted) {
        setState(() {
          _report = Api.parseDailyReport(body);
          _loadingReport = false;
          _staleReport = false;
          _errReport = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_report == null) {
        setState(() { _errReport = e.toString(); _loadingReport = false; });
      } else {
        setState(() { _loadingReport = false; _staleReport = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络开小差了，当前显示的是缓存内容')));
      }
    }
  }

  Future<void> _loadDnews({bool silent = false}) async {
    if (!silent) setState(() { _loadingDnews = true; _errDnews = null; });
    final cj = Store.cacheDnewsJson;
    if (cj != null && _dnews == null) {
      try {
        final d = Api.parseDailyNews(cj);
        if (mounted) setState(() { _dnews = d; _loadingDnews = false; _staleDnews = true; });
      } catch (_) {}
    }
    try {
      final body = await Api.fetchDailyNewsBody();
      Store.cacheDnewsJson = body;
      Store.cacheDnewsAt = DateTime.now().millisecondsSinceEpoch;
      if (mounted) {
        setState(() {
          _dnews = Api.parseDailyNews(body);
          _loadingDnews = false;
          _staleDnews = false;
          _errDnews = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_dnews == null) {
        setState(() { _errDnews = e.toString(); _loadingDnews = false; });
      } else {
        setState(() { _loadingDnews = false; _staleDnews = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络开小差了，当前显示的是缓存内容')));
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadHot({bool silent = false}) async {
    if (!silent) setState(() { _loadingHot = true; _errHot = null; });
    final cj = Store.cacheHotJson;
    if (cj != null && _hot == null) {
      try {
        final h = Api.parseHot(cj);
        if (mounted) setState(() { _hot = h; _loadingHot = false; _staleHot = true; });
      } catch (_) {}
    }
    try {
      final body = await Api.fetchHotBody();
      Store.cacheHotJson = body;
      Store.cacheHotAt = DateTime.now().millisecondsSinceEpoch;
      if (mounted) {
        setState(() {
          _hot = Api.parseHot(body);
          _loadingHot = false;
          _staleHot = false;
          _errHot = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_hot == null) {
        setState(() { _errHot = e.toString(); _loadingHot = false; });
      } else {
        setState(() { _loadingHot = false; _staleHot = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络开小差了，当前显示的是缓存内容')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      _overviewCard(c),
      TabBar(
        controller: _tab,
        tabs: const [Tab(text: '🗞️ AI 日报'), Tab(text: '📰 每日新闻'), Tab(text: '🔥 技术热榜')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _buildReport(c),
            _buildDnews(c),
            _buildHot(c),
          ],
        ),
      ),
    ]);
  }

  String _cacheTag(int at) {
    if (at <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // 今日速览卡：横跨三个来源的总览 + 一键 AI 划重点
  Widget _overviewCard(ColorScheme c) {
    final total = (_report?.count ?? 0) + (_dnews?.items.length ?? 0) + (_hot?.length ?? 0);
    int loaded = 0;
    if (_report != null) loaded++;
    if (_dnews != null) loaded++;
    if (_hot != null) loaded++;
    final hasContent = total > 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('📊 今日速览', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('共 $total 条 · 已加载 $loaded/3 来源', style: TextStyle(fontSize: 11, color: c.outline)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _srcChip(c, 'AI 日报', _report == null ? null : Store.cacheReportAt, _staleReport),
            _srcChip(c, '每日新闻', _dnews == null ? null : Store.cacheDnewsAt, _staleDnews),
            _srcChip(c, '技术热榜', _hot == null ? null : Store.cacheHotAt, _staleHot),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('🤖 AI 帮你划 3 条重点'),
              onPressed: hasContent ? _aiTop3 : null,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _srcChip(ColorScheme c, String name, int? at, bool stale) {
    final loading = at == null;
    final tag = loading ? '加载中…' : _cacheTag(at);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(loading ? Icons.hourglass_empty : Icons.check_circle_outline, size: 14,
          color: loading ? c.outline : c.primary),
      label: Text('$name · $tag${stale && !loading ? ' · 缓存' : ''}', style: const TextStyle(fontSize: 11)),
    );
  }

  // 把今天三个来源的内容压成标题摘要，交给 AI 挑 3 条重点
  void _aiTop3() {
    if (aiAskGlobal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 还没准备好，去设置里填好 Key 再试')));
      return;
    }
    final digest = _buildDigest();
    const head = '下面是今天我的个人工作台收集到的资讯速览（只有标题）。请从中挑出最值得我这个普通用户关注的 3 条，用大白话分别说明：①这大概是什么 ②为什么值得关注 ③对我有什么实际用处。别扯编号以外的废话。\n\n';
    aiAskGlobal!(head + digest);
  }

  String _buildDigest() {
    final b = StringBuffer();
    if (_report != null) {
      b.writeln('【AI 日报】');
      for (final s in _report!.sections) {
        b.writeln('· ${s.label}');
        for (final it in s.items.take(5)) {
          b.writeln('  - ${it.title}');
        }
      }
    }
    if (_dnews != null) {
      b.writeln('【每日新闻】');
      for (final it in _dnews!.items.take(12)) {
        b.writeln('· ${it.title}');
      }
    }
    if (_hot != null) {
      b.writeln('【技术热榜】');
      for (final it in _hot!.take(12)) {
        b.writeln('· ${it.title}');
      }
    }
    return b.toString();
  }

  Widget _buildReport(ColorScheme c) {
    if (_loadingReport && _report == null) return const Center(child: CircularProgressIndicator());
    if (_errReport != null && _report == null) {
      return _err(c, _errReport!, () => _loadReport());
    }
    final r = _report!;
    return RefreshIndicator(
      onRefresh: () => _loadReport(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${r.date} AI 日报 · ${r.count} 条', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('数据源 ${r.source} · ${r.fetchedAt}${_staleReport ? ' · ⚡离线缓存 ${_cacheTag(Store.cacheReportAt)}' : ''}',
              style: TextStyle(fontSize: 11, color: c.outline)),
          const SizedBox(height: 10),
          ...r.sections.map((s) => _sectionCard(s, ask: '用大白话展开讲讲这条 AI 新闻的背景和影响，并说说对我有什么用：')),
        ],
      ),
    );
  }

  Widget _buildDnews(ColorScheme c) {
    // 尚未加载（每日新闻 Tab 懒加载，启动时 _dnews 为 null）先给占位，避免空指针崩溃
    if (_dnews == null) {
      if (_errDnews != null) return _err(c, _errDnews!, () => _loadDnews());
      return const Center(child: CircularProgressIndicator());
    }
    final d = _dnews!;
    return RefreshIndicator(
      onRefresh: () => _loadDnews(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${d.date} 每日新闻 · ${d.items.length} 条', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('数据源 ${d.source}${_staleDnews ? ' · ⚡离线缓存 ${_cacheTag(Store.cacheDnewsAt)}' : ''}',
              style: TextStyle(fontSize: 11, color: c.outline)),
          if (d.tip.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('💡 ${d.tip}', style: TextStyle(fontStyle: FontStyle.italic, color: c.outline))),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📌 今日头条', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...d.items.asMap().entries.map((e) => _newsTile(
                  title: '${e.key + 1}. ${e.value.title}',
                  item: e.value,
                  ask: '用大白话展开讲讲这条新闻的背景，并说说对我有什么影响：',
                )),
          ]))),
        ],
      ),
    );
  }

  Widget _buildHot(ColorScheme c) {
    if (_loadingHot && _hot == null) return const Center(child: CircularProgressIndicator());
    if (_errHot != null && _hot == null) {
      return _err(c, _errHot!, () => _loadHot());
    }
    final list = _hot!;
    return RefreshIndicator(
      onRefresh: () => _loadHot(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('V2EX 技术热帖 · ${list.length} 条', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('数据源 V2EX${_staleHot ? ' · ⚡离线缓存 ${_cacheTag(Store.cacheHotAt)}' : ''}', style: TextStyle(fontSize: 11, color: c.outline)),
          const SizedBox(height: 10),
          ...list.asMap().entries.map((e) => _hotTile(c, e.value)),
        ],
      ),
    );
  }

  Widget _hotTile(ColorScheme c, V2exItem it) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.title, style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
          if (it.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(it.content, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: c.outline)),
            ),
          const SizedBox(height: 6),
          Text(
            [
              if (it.node.isNotEmpty) it.node,
              if (it.by.isNotEmpty) '@${it.by}',
              '💬 ${it.replies}',
              if (it.created > 0) _fmtTs(it.created),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 11, color: c.outline),
          ),
          const SizedBox(height: 4),
          Row(children: [
            TextButton(onPressed: () => launchUrl(Uri.parse(it.link), mode: LaunchMode.externalApplication),
                child: const Text('原文 ↗', style: TextStyle(fontSize: 12))),
            TextButton.icon(
              icon: const Icon(Icons.star_border, size: 16),
              label: const Text('收藏', style: TextStyle(fontSize: 12)),
              onPressed: () => _favHot(it),
            ),
            if (aiAskGlobal != null)
              TextButton(
                onPressed: () => aiAskGlobal!('用大白话讲讲这个技术热点是什么、为什么这么火：${it.title}'),
                child: const Text('☁️ 让 AI 讲讲', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ]),
      ),
    );
  }

  void _favHot(V2exItem it) {
    final favs = Store.favs();
    if (favs.any((f) => f.title == it.title)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这条已经收藏过了')));
      return;
    }
    Store.saveFavs([Fav(it.title, it.link, 'V2EX', DateTime.now().millisecondsSinceEpoch), ...favs]);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⭐ 已收藏')));
  }

  String _fmtTs(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}-${d.day} $hh:$mm';
  }

  Widget _sectionCard(NewsSection s, {required String ask}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.label, size: 18),
        title: Text('${s.label}（${s.items.length}）', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        children: s.items.map((it) => _newsTile(title: it.title, item: it, ask: ask)).toList(),
      ),
    );
  }

  void _fav(NewsItem item) {
    final favs = Store.favs();
    if (favs.any((f) => f.title == item.title)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这条已经收藏过了')));
      return;
    }
    Store.saveFavs([Fav(item.title, item.url, item.source, DateTime.now().millisecondsSinceEpoch), ...favs]);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⭐ 已收藏')));
  }

  Widget _newsTile({required String title, required NewsItem item, required String ask}) {
    final c = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, height: 1.4)),
      if (item.summary.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.outline)),
        ),
      Row(children: [
        if (item.source.isNotEmpty) Text(item.source, style: TextStyle(fontSize: 11, color: c.outline)),
        const Spacer(),
        if (item.url.isNotEmpty)
          TextButton(onPressed: () => launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication), child: const Text('原文 ↗', style: TextStyle(fontSize: 12))),
        TextButton.icon(
          icon: const Icon(Icons.star_border, size: 16),
          label: const Text('收藏', style: TextStyle(fontSize: 12)),
          onPressed: () => _fav(item),
        ),
        if (aiAskGlobal != null)
          TextButton(
            onPressed: () => aiAskGlobal!(ask + item.title),
            child: const Text('☁️ 让 AI 讲讲', style: TextStyle(fontSize: 12)),
          ),
      ]),
      const Divider(height: 16),
    ]);
  }

  // 把英文异常转成用户能看懂的中文提示
  String _friendlyErr(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('http')) return '网络请求失败了，可能是当前网络不稳定，或新闻接口暂时不可用。';
    if (m.contains('timeout') || m.contains('超时')) return '连接超时了，请检查网络后重试。';
    if (m.contains('socket') || m.contains('failed host') || m.contains('网络')) return '网络连接失败，请检查你的网络是否正常。';
    return '内容加载失败了，点下面的按钮再试一次。';
  }

  Widget _err(ColorScheme c, String msg, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('⚠️ 加载失败', style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_friendlyErr(msg), textAlign: TextAlign.center, style: TextStyle(color: c.onSurface)),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center,
              style: TextStyle(color: c.outline.withValues(alpha: 0.6), fontSize: 11)),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('重试')),
        ]),
      ),
    );
  }
}
