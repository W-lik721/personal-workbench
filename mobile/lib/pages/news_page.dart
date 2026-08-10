// 新闻页：AI 日报 + 每日新闻（TabBar 切换）
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
  bool _loadingDnews = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadReport();
    _loadDnews();
  }

  Future<void> _loadReport() async {
    setState(() { _loadingReport = true; _errReport = null; });
    try {
      final r = await Api.fetchDailyReport();
      if (mounted) setState(() { _report = r; _loadingReport = false; });
    } catch (e) {
      if (mounted) setState(() { _errReport = e.toString(); _loadingReport = false; });
    }
  }

  Future<void> _loadDnews() async {
    setState(() { _loadingDnews = true; _errDnews = null; });
    try {
      final r = await Api.fetchDailyNews();
      if (mounted) setState(() { _dnews = r; _loadingDnews = false; });
    } catch (e) {
      if (mounted) setState(() { _errDnews = e.toString(); _loadingDnews = false; });
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

  Widget _buildReport(ColorScheme c) {
    if (_loadingReport) return const Center(child: CircularProgressIndicator());
    if (_errReport != null) {
      return _err(c, _errReport!, () => _loadReport());
    }
    final r = _report!;
    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${r.date} AI 日报 · ${r.count} 条', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('数据源 ${r.source} · ${r.fetchedAt}', style: TextStyle(fontSize: 11, color: c.outline)),
          const SizedBox(height: 10),
          ...r.sections.map((s) => _sectionCard(s, ask: '用大白话展开讲讲这条 AI 新闻的背景和影响，并说说对我有什么用：')),
        ],
      ),
    );
  }

  Widget _buildDnews(ColorScheme c) {
    if (_loadingDnews) return const Center(child: CircularProgressIndicator());
    if (_errDnews != null) {
      return _err(c, _errDnews!, () => _loadDnews());
    }
    final d = _dnews!;
    return RefreshIndicator(
      onRefresh: _loadDnews,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${d.date} 每日新闻 · ${d.items.length} 条', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('数据源 ${d.source}', style: TextStyle(fontSize: 11, color: c.outline)),
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
          onPressed: () {
            Store.saveFavs([Fav(item.title, item.url, item.source, DateTime.now().millisecondsSinceEpoch), ...Store.favs()]);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⭐ 已收藏')));
          },
        ),
        // 让 AI 讲讲：切到 AI tab 需要全局回调，这里直接 popup 提示（由 main 注入）
        if (aiAskGlobal != null)
          TextButton(
            onPressed: () => aiAskGlobal!(ask + item.title),
            child: const Text('☁️ 让 AI 讲讲', style: TextStyle(fontSize: 12)),
          ),
      ]),
      const Divider(height: 16),
    ]);
  }

  Widget _err(ColorScheme c, String msg, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('⚠️ 加载失败', style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center, style: TextStyle(color: c.outline)),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('重试')),
        ]),
      ),
    );
  }
}
