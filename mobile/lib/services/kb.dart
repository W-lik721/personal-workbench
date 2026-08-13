// 知识库服务：App AI 助手读电脑 vault 知识库（经 GitHub vault-backup 中转）
// ① 拉 kb-index.json 索引 → 按问题关键词匹配 → 拉相关笔记全文拼给 AI
// ② 记忆入库：把 AI 长期记忆导出 md 上传到 vault 的 05-数字分身/App记忆/ 分区
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core.dart';

class Kb {
  static List<dynamic> _idx = []; // 索引缓存（内存，每次会话拉一次）

  static Map<String, String> _h(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'lite-workbench',
      };

  // 拉取并解析 kb-index.json（失败返回空列表，err 存原因）
  static Future<List<dynamic>> index(String token, String repo, String branch) async {
    if (_idx.isNotEmpty) return _idx;
    final uri = Uri.parse('https://api.github.com/repos/$repo/contents/kb-index.json?ref=$branch');
    try {
      final r = await http.get(uri, headers: _h(token)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        return [];
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final content = base64Decode((j['content'] as String).replaceAll('\n', ''));
      final idx = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      _idx = (idx['files'] as List? ?? []);
      return _idx;
    } catch (_) {
      return [];
    }
  }

  // 按问题关键词匹配索引，返回 top-K 文件（命中 title/preview 的词语数排序）
  static List<Map<String, dynamic>> search(List<dynamic> idx, String query, {int limit = 3}) {
    // 词表：分隔出的词条 + 中文 2 字滑窗（覆盖连续中文，如"怎么避坑"→"避坑"）
    final words = <String>{};
    final parts = query.split(RegExp(r'[\s,，。！？!?、;；:：()（）]+'));
    final cjk2 = RegExp(r'^[\u4e00-\u9fff]{2}$');
    for (final p in parts) {
      if (p.isEmpty) continue;
      if (p.length >= 2) words.add(p);
      for (var i = 0; i + 2 <= p.length; i++) {
        final big = p.substring(i, i + 2);
        if (cjk2.hasMatch(big)) words.add(big);
      }
    }
    final scored = <Map<String, dynamic>>[];
    for (final f in idx) {
      if (f is! Map) continue;
      final title = (f['title'] ?? '').toString();
      final preview = (f['preview'] ?? '').toString();
      final hay = '$title $preview';
      int score = 0;
      for (final w in words) {
        if (hay.contains(w)) score++;
      }
      if (score > 0) scored.add({'file': f, 'score': score});
    }
    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return scored.take(limit).map((e) => (e['file'] as Map).cast<String, dynamic>()).toList();
  }

  // 拉取一篇笔记全文（截断到 maxChars 防 prompt 撑爆）
  static Future<String> doc(String token, String repo, String branch, String path, {int maxChars = 3000}) async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/contents/${Uri.encodeComponent(path)}?ref=$branch');
    try {
      final r = await http.get(uri, headers: _h(token)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return '';
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final content = base64Decode((j['content'] as String).replaceAll('\n', ''));
      final t = utf8.decode(content);
      return t.length <= maxChars ? t : t.substring(0, maxChars);
    } catch (_) {
      return '';
    }
  }

  // 一站式：查知识库 → 返回可拼进 prompt 的上下文（无匹配返回空串）
  static Future<String> query(String question) async {
    final token = await Store.syncToken();
    if (token.isEmpty || !Store.kbOn) return '';
    final repo = Store.kbRepo;
    final branch = Store.kbBranch;
    final idx = await index(token, repo, branch);
    if (idx.isEmpty) return '';
    final hits = search(idx, question);
    if (hits.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('【参考我的知识库（vault）】');
    for (final h in hits) {
      final body = await doc(token, repo, branch, h['path'] as String);
      if (body.isEmpty) continue;
      sb.writeln('--- 《${h['title']}》 ---');
      sb.writeln(body);
      sb.writeln();
    }
    sb.writeln('（以上是知识库相关笔记，回答时优先参考，但涉及数字/价格/时效信息要说明来源可信度）');
    return sb.toString();
  }

  // 记忆入库：AI 长期记忆 + 对话统计 → md → 上传 vault 05-数字分身/App记忆/
  static Future<void> uploadMemory(String token, String repo) async {
    final memory = Store.aiMemory();
    final now = DateTime.now();
    final ds = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final path = '05-数字分身/App记忆/$ds-ai-memory.md';
    final sb = StringBuffer();
    sb.writeln('# App AI 记忆快照 · $ds');
    sb.writeln();
    sb.writeln('> 由轻量工作台 App「记忆入库」自动生成，勿手改（历史按日期保留）。');
    sb.writeln();
    sb.writeln('## AI 长期记忆（${memory.length} 条）');
    sb.writeln();
    if (memory.isEmpty) {
      sb.writeln('（暂无长期记忆）');
    } else {
      memory.asMap().forEach((i, m) => sb.writeln('${i + 1}. $m'));
    }
    sb.writeln();
    sb.writeln('## 对话历史条数');
    sb.writeln('- 共 ${Store.aiHistory().length} 条消息（仅记条数，正文不上传）');
    await _put(token, repo, path, 'App AI 记忆入库 $ds', sb.toString());
  }

  // 速记入库：把 App 的速记快照上传到 vault 的 05-数字分身/App速记/
  static Future<void> uploadNotes(String token, String repo) async {
    final notes = Store.notes();
    final now = DateTime.now();
    final ds = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final path = '05-数字分身/App速记/$ds-速记.md';
    final sb = StringBuffer();
    sb.writeln('# App 速记快照 · $ds');
    sb.writeln();
    sb.writeln('> 由轻量工作台 App「速记入库」自动生成，勿手改（历史按日期保留）。');
    sb.writeln();
    sb.writeln('## 速记（${notes.length} 条）');
    sb.writeln();
    if (notes.isEmpty) {
      sb.writeln('（暂无速记）');
    } else {
      notes.asMap().forEach((i, n) => sb.writeln('${i + 1}. ${n.text}'));
    }
    await _put(token, repo, path, 'App 速记入库 $ds', sb.toString());
  }

  // 上传 md 到仓库指定路径（已存在则带 sha 更新）
  static Future<void> _put(String token, String repo, String path, String msg, String md) async {
    final content = base64Encode(utf8.encode(md));
    final uri = Uri.parse('https://api.github.com/repos/$repo/contents/${Uri.encodeComponent(path)}');
    // 先查 sha（已存在则更新）
    String? sha;
    final r0 = await http.get(uri, headers: _h(token)).timeout(const Duration(seconds: 20));
    if (r0.statusCode == 200) {
      final j = jsonDecode(utf8.decode(r0.bodyBytes)) as Map<String, dynamic>;
      sha = j['sha'] as String?;
    } else if (r0.statusCode != 404) {
      throw Exception('云端查询失败 HTTP ${r0.statusCode}');
    }
    final resp = await http.put(
      uri,
      headers: {..._h(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': msg,
        'content': content,
        if (sha != null) 'sha': sha,
      }),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      final err = utf8.decode(resp.bodyBytes);
      throw Exception('上传失败 HTTP ${resp.statusCode}：${err.length > 160 ? err.substring(0, 160) : err}');
    }
  }
}
