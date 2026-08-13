// 内置 Skill 方法库：App 安装包自带的 31 个方法论型 skill 说明书（离线可用）
// 与知识库（kb.dart 云端检索）互补：内置库=稳定离线，知识库=动态扩展
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class SkillLib {
  static List<dynamic> _skills = []; // [{name, desc, body}]
  static bool _loaded = false;

  // 从打包 assets 加载（首次调用时；失败静默，不阻塞聊天）
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/skill_lib.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _skills = (j['skills'] as List? ?? []);
      _loaded = true;
    } catch (_) {
      _skills = [];
      _loaded = true;
    }
  }

  static bool get ready => _loaded && _skills.isNotEmpty;
  static int get count => _skills.length;

  // 分词：词条 + 中文 2 字滑窗（与 Kb.search 同款，抽出来便于测试）
  static Set<String> wordSet(String query) {
    final cjk2 = RegExp(r'^[\u4e00-\u9fff]{2}$');
    final words = <String>{};
    for (final p in query.split(RegExp(r'[\s,，。！？!?、;；:：()（）]+'))) {
      if (p.isEmpty) continue;
      if (p.length >= 2) words.add(p);
      for (var i = 0; i + 2 <= p.length; i++) {
        final big = p.substring(i, i + 2);
        if (cjk2.hasMatch(big)) words.add(big);
      }
    }
    return words;
  }

  static int matchCount(String hay, Set<String> words) {
    int score = 0;
    for (final w in words) {
      if (hay.contains(w)) score++;
    }
    return score;
  }

  // 与 Kb.search 相同的匹配逻辑：命中 name/desc/body 计数
  static List<Map<String, dynamic>> search(String query, {int limit = 3}) {
    final words = wordSet(query);
    final scored = <Map<String, dynamic>>[];
    for (final s in _skills) {
      if (s is! Map) continue;
      final hay = '${s['name']} ${s['desc']} ${s['body']}';
      final score = matchCount(hay, words);
      if (score > 0) scored.add({'skill': s, 'score': score});
    }
    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return scored.take(limit).map((e) => (e['skill'] as Map).cast<String, dynamic>()).toList();
  }

  // 一站式：匹配内置 skill 方法 → 拼接上下文块（无命中返回空）
  static String query(String question) {
    if (!ready) return '';
    final hits = search(question);
    if (hits.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('【参考内置 Skill 方法库】');
    for (final h in hits) {
      final name = (h['name'] ?? '').toString();
      final body = (h['body'] ?? '').toString();
      final keep = body.length <= 3500 ? body : body.substring(0, 3500);
      sb.writeln('--- Skill《$name》---');
      sb.writeln(keep);
      sb.writeln();
    }
    sb.writeln('（按以上 skill 的方法论来回答，保持可操作）');
    return sb.toString();
  }
}
