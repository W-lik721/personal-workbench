// 数据模型 + 本地存储 + 网络 API（纯 Dart，无第三方 UI 依赖）
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// 新闻页"让 AI 讲讲"跳转 AI tab 的全局桥（由 main.dart 注入）
void Function(String text)? aiAskGlobal;

// ---------- 模型 ----------
class Todo {
  String text;
  bool done;
  Todo(this.text, {this.done = false});
  Map<String, dynamic> toJson() => {'text': text, 'done': done};
  Todo.fromJson(Map<String, dynamic> j) : text = j['text'] ?? '', done = j['done'] ?? false;
}

class Note {
  String text;
  int at;
  Note(this.text, this.at);
  Map<String, dynamic> toJson() => {'text': text, 'at': at};
  Note.fromJson(Map<String, dynamic> j) : text = j['text'] ?? '', at = j['at'] ?? 0;
}

class Fav {
  String title, url, source;
  int at;
  Fav(this.title, this.url, this.source, this.at);
  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'source': source, 'at': at};
  Fav.fromJson(Map<String, dynamic> j)
      : title = j['title'] ?? '',
        url = j['url'] ?? '',
        source = j['source'] ?? '',
        at = j['at'] ?? 0;
}

class Link {
  String label, url;
  Link(this.label, this.url);
  Map<String, dynamic> toJson() => {'label': label, 'url': url};
  Link.fromJson(Map<String, dynamic> j) : label = j['label'] ?? '', url = j['url'] ?? '';
}

class Course {
  String dow, time, name, location, teacher, note;
  Course({this.dow = '', this.time = '', this.name = '', this.location = '', this.teacher = '', this.note = ''});
  Map<String, dynamic> toJson() => {'dow': dow, 'time': time, 'name': name, 'location': location, 'teacher': teacher, 'note': note};
  Course.fromJson(Map<String, dynamic> j)
      : dow = j['dow'] ?? '',
        time = j['time'] ?? '',
        name = j['name'] ?? '',
        location = j['location'] ?? '',
        teacher = j['teacher'] ?? '',
        note = j['note'] ?? '';
}

class NewsItem {
  String title, summary, source, url;
  NewsItem({required this.title, this.summary = '', this.source = '', this.url = ''});
}

class NewsSection {
  String label;
  List<NewsItem> items;
  NewsSection(this.label, this.items);
}

class DailyReport {
  String date, source, fetchedAt;
  int count;
  List<NewsSection> sections;
  DailyReport({this.date = '', this.source = '', this.fetchedAt = '', this.count = 0, this.sections = const []});
}

class DailyNews {
  String date, source, tip;
  List<NewsItem> items;
  DailyNews({this.date = '', this.source = '', this.tip = '', this.items = const []});
}

// ---------- 本地存储 ----------
class Store {
  static SharedPreferences? _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static List<Todo> todos() => _load('wb_todos').map((j) => Todo.fromJson(j)).toList();
  static void saveTodos(List<Todo> l) => _save('wb_todos', l.map((t) => t.toJson()).toList());
  static List<Note> notes() => _load('wb_notes').map((j) => Note.fromJson(j)).toList();
  static void saveNotes(List<Note> l) => _save('wb_notes', l.map((n) => n.toJson()).toList());
  static List<Fav> favs() => _load('wb_favs').map((j) => Fav.fromJson(j)).toList();
  static void saveFavs(List<Fav> l) => _save('wb_favs', l.map((f) => f.toJson()).toList());
  static List<Link> links() => _load('wb_links').map((j) => Link.fromJson(j)).toList();
  static void saveLinks(List<Link> l) => _save('wb_links', l.map((x) => x.toJson()).toList());
  static List<Course> courses() => _load('wb_schedule').map((j) => Course.fromJson(j)).toList();
  static void saveCourses(List<Course> l) => _save('wb_schedule', l.map((c) => c.toJson()).toList());

  static bool get darkMode => _p?.getBool('wb_dark') ?? true;
  static set darkMode(bool v) => _p?.setBool('wb_dark', v);
  static String get aiProv => _p?.getString('wb_ai_prov') ?? 'agnes';
  static set aiProv(String v) => _p?.setString('wb_ai_prov', v);
  static String aiKey(String prov) => _p?.getString('wb_ai_key_$prov') ?? '';
  static void setAiKey(String prov, String k) => _p?.setString('wb_ai_key_$prov', k);

  static List<dynamic> _load(String k) {
    try {
      final s = _p?.getString(k);
      return s == null ? [] : (jsonDecode(s) as List);
    } catch (_) {
      return [];
    }
  }
  static void _save(String k, List<dynamic> v) => _p?.setString(k, jsonEncode(v));
}

// ---------- 网络 API ----------
class Api {
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36';

  // AI 日报：aihot 公开接口
  static Future<DailyReport> fetchDailyReport() async {
    final r = await http.get(Uri.parse('https://aihot.virxact.com/api/public/daily'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('日报接口 HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final secs = (j['sections'] as List? ?? []).map((s) {
      final sm = s as Map<String, dynamic>;
      final items = (sm['items'] as List? ?? []).map((it) {
        final im = it as Map<String, dynamic>;
        return NewsItem(
          title: im['title'] ?? '',
          summary: im['summary'] ?? '',
          source: im['source'] ?? '',
          url: im['url'] ?? '',
        );
      }).toList();
      return NewsSection(sm['label'] ?? '', items);
    }).toList();
    var count = 0;
    for (final s in secs) count += s.items.length;
    return DailyReport(
      date: j['date'] ?? '',
      source: 'AI HOT',
      fetchedAt: (j['generatedAt'] ?? '').toString().replaceAll('T', ' '),
      count: count,
      sections: secs,
    );
  }

  // 每日新闻：60s 公开接口
  static Future<DailyNews> fetchDailyNews() async {
    final r = await http.get(Uri.parse('https://60s-api.viki.moe/v2/60s'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('新闻接口 HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final data = j['data'] as Map<String, dynamic>? ?? {};
    final news = (data['news'] as List? ?? []).map((t) => NewsItem(title: t.toString(), source: '每日60秒')).toList();
    return DailyNews(
      date: data['date'] ?? '',
      source: '每日60秒',
      tip: data['note'] ?? data['tip'] ?? '',
      items: news,
    );
  }

  // AI 助手：Agnes / 智谱
  static const aiProviders = {
    'agnes': {'label': 'Agnes 2.5 Flash', 'url': 'https://apihub.agnes-ai.cn/v1/chat/completions', 'model': 'agnes-2.5-flash'},
    'glm': {'label': '智谱 GLM Flash', 'url': 'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'model': 'glm-4-flash'},
  };
  static Future<String> chat(String prov, String key, List<Map<String, String>> history, String question) async {
    final p = aiProviders[prov]!;
    final msgs = [
      {'role': 'system', 'content': '你是用户个人工作台的 AI 助手，用中文大白话回答，简洁、可操作。'},
      ...history,
      {'role': 'user', 'content': question},
    ];
    final r = await http.post(Uri.parse(p['url']!),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
        body: jsonEncode({'model': p['model'], 'messages': msgs, 'max_tokens': prov == 'agnes' ? 4000 : 800}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 401) throw Exception('Key 无效或已过期');
    if (r.statusCode == 429) throw Exception('请求太频繁（限流），稍等再试');
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final msg = ((j['choices'] as List? ?? []) as List).isNotEmpty ? (j['choices'][0] as Map)['message'] as Map? : null;
    final content = msg?['content']?.toString().trim() ?? '';
    if (content.isNotEmpty) return content;
    final reasoning = msg?['reasoning_content']?.toString();
    if (reasoning != null && reasoning.isNotEmpty) return '（思考中：）\n$reasoning';
    return '（空回复）';
  }
}
