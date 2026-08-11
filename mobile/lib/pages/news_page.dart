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
  String? _errReport;
  String? _errDnews;
  bool _loadingReport = true;
  bool _loadingDnews = false;
  bool _staleReport = false; // 当前日报来自缓存
  bool _staleDnews = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    // 懒加载：切到"每日新闻"才首次请求
    _tab.addListener(() {
      if (_tab.index == 1 && _dnews == null && !_loadingDnews) _loadDnews();
    });
    _loadReport();
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

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      TabBar(
        controller: _tab,
        tabs: const [Tab(text: '🗞️ AI 日报'), Tab(text: '📰 每日新闻')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _buildReport(c),
            _buildDnews(c),
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
