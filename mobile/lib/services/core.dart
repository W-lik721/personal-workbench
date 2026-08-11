// 数据模型 + 本地存储 + 网络 API（纯 Dart，无第三方 UI 依赖）
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// 新闻页"让 AI 讲讲"跳转 AI tab 的全局桥（由 main.dart 注入）
void Function(String text)? aiAskGlobal;
// AI 页注册：填充输入框（配合 aiAskGlobal 使用）
void Function(String text)? aiFillGlobal;
// 设置页"清空对话历史"通知 AI 页同步清空的全局回调（由 AiPage 注册）
void Function()? aiClearGlobal;

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
  static const _sec = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 必须在 main() 里 await 一次：初始化 SharedPreferences + 加密存储
  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

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

  // API Key：走系统加密存储（Keystore），不落明文
  static Future<String> aiKey(String prov) async {
    try {
      return await _sec.read(key: 'wb_ai_key_$prov') ?? '';
    } catch (_) {
      return '';
    }
  }
  static Future<void> setAiKey(String prov, String k) async {
    try {
      if (k.isEmpty) {
        await _sec.delete(key: 'wb_ai_key_$prov');
      } else {
        await _sec.write(key: 'wb_ai_key_$prov', value: k);
      }
    } catch (_) {}
  }

  // ---------- 日报/新闻缓存（原始 JSON + 抓取时间） ----------
  static String? get cacheReportJson => _p?.getString('wb_cache_report');
  static set cacheReportJson(String? v) => v == null ? _p?.remove('wb_cache_report') : _p?.setString('wb_cache_report', v);
  static int get cacheReportAt => _p?.getInt('wb_cache_report_at') ?? 0;
  static set cacheReportAt(int v) => _p?.setInt('wb_cache_report_at', v);
  static String? get cacheDnewsJson => _p?.getString('wb_cache_dnews');
  static set cacheDnewsJson(String? v) => v == null ? _p?.remove('wb_cache_dnews') : _p?.setString('wb_cache_dnews', v);
  static int get cacheDnewsAt => _p?.getInt('wb_cache_dnews_at') ?? 0;
  static set cacheDnewsAt(int v) => _p?.setInt('wb_cache_dnews_at', v);

  // ---------- AI 记忆 ----------
  // 对话历史（role+content），自动保存/恢复
  static List<Map<String, String>> aiHistory() => _load('wb_ai_history').map((j) {
        final m = j as Map;
        return {'role': m['role']?.toString() ?? 'user', 'content': m['content']?.toString() ?? ''};
      }).toList();
  static void saveAiHistory(List<Map<String, String>> l) => _save('wb_ai_history', l);
  // 长期记忆（用户点"记住"或手动添加的关键信息）
  static List<String> aiMemory() => _load('wb_ai_memory').map((j) => j.toString()).toList();
  static void saveAiMemory(List<String> l) => _save('wb_ai_memory', l);
  // 记忆开关：关掉后不再保存新历史、发消息也不带记忆
  static bool get aiMemoryOn => _p?.getBool('wb_ai_memory_on') ?? true;
  static set aiMemoryOn(bool v) => _p?.setBool('wb_ai_memory_on', v);
  // 发送时携带的历史条数上限（消息条数，默认 20 = 最近 10 轮对话）
  static int get aiMemoryMax => _p?.getInt('wb_ai_memory_max') ?? 20;
  static set aiMemoryMax(int v) => _p?.setInt('wb_ai_memory_max', v);

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

  // AI 日报：aihot 公开接口（返回原始 JSON 字符串，便于缓存）
  static Future<String> fetchDailyReportBody() async {
    final r = await http.get(Uri.parse('https://aihot.virxact.com/api/public/daily'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('日报接口 HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes);
  }

  static DailyReport parseDailyReport(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
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

  // 每日新闻：60s 公开接口（返回原始 JSON 字符串，便于缓存）
  static Future<String> fetchDailyNewsBody() async {
    final r = await http.get(Uri.parse('https://60s-api.viki.moe/v2/60s'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('新闻接口 HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes);
  }

  static DailyNews parseDailyNews(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
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

  static List<Map<String, String>> _buildMsgs(List<Map<String, String>> history, String question,
      {List<String> memory = const []}) {
    final memBlock = memory.isEmpty
        ? ''
        : '\n\n【关于用户的长期记忆，对话时请自然运用这些信息】\n- ${memory.join('\n- ')}';
    return [
      {'role': 'system', 'content': '你是用户个人工作台的 AI 助手，用中文大白话回答，简洁、可操作。$memBlock'},
      ...history,
      {'role': 'user', 'content': question},
    ];
  }

  static void _checkStatus(int code) {
    if (code == 401) throw Exception('Key 无效或已过期，请重新填写');
    if (code == 429) throw Exception('问得太快了，休息几秒再试');
    if (code != 200) throw Exception('网络开小差了（HTTP $code），稍后重试');
  }

  // 流式对话：逐字回调 onChunk（SSE）。client 可外部传入以便中途 close() 停止
  static Future<void> chatStream(String prov, String key, List<Map<String, String>> history, String question,
      {List<String> memory = const [], http.Client? client, required void Function(String chunk) onChunk}) async {
    final p = aiProviders[prov]!;
    final req = http.Request('POST', Uri.parse(p['url']!))
      ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer $key'})
      ..body = jsonEncode({
        'model': p['model'],
        'messages': _buildMsgs(history, question, memory: memory),
        'max_tokens': prov == 'agnes' ? 4000 : 2000,
        'stream': true,
      });
    final c = client ?? http.Client();
    final resp = await c.send(req).timeout(const Duration(seconds: 90));
    _checkStatus(resp.statusCode);
    var full = '';
    String? reasoning;
    await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final t = line.trim();
      if (t.isEmpty || !t.startsWith('data:')) continue;
      final data = t.substring(5).trim();
      if (data == '[DONE]') break;
      try {
        final j = jsonDecode(data) as Map<String, dynamic>;
        final delta = ((j['choices'] as List? ?? []) as List).isNotEmpty ? (j['choices'][0] as Map)['delta'] as Map? : null;
        final c = delta?['content']?.toString();
        if (c != null && c.isNotEmpty) {
          full += c;
          onChunk(c);
        }
        final rc = delta?['reasoning_content']?.toString();
        if (rc != null && rc.isNotEmpty) reasoning = (reasoning ?? '') + rc;
      } catch (_) {}
    }
    if (full.trim().isEmpty) {
      final rc = reasoning?.trim();
      if (rc != null && rc.isNotEmpty) {
        onChunk('\n（模型思考过程：）\n$rc');
        return;
      }
      throw Exception('模型没有给出回答，再试一次？');
    }
  }

  // 非流式兜底（个别端点不支持 stream 时可用）
  static Future<String> chat(String prov, String key, List<Map<String, String>> history, String question,
      {List<String> memory = const []}) async {
    final p = aiProviders[prov]!;
    final r = await http.post(Uri.parse(p['url']!),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
        body: jsonEncode({
          'model': p['model'],
          'messages': _buildMsgs(history, question, memory: memory),
          'max_tokens': prov == 'agnes' ? 4000 : 2000,
        })).timeout(const Duration(seconds: 60));
    _checkStatus(r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final msg = ((j['choices'] as List? ?? []) as List).isNotEmpty ? (j['choices'][0] as Map)['message'] as Map? : null;
    final content = msg?['content']?.toString().trim() ?? '';
    if (content.isNotEmpty) return content;
    final reasoning = msg?['reasoning_content']?.toString();
    if (reasoning != null && reasoning.isNotEmpty) return '（思考中：）\n$reasoning';
    return '（空回复）';
  }
}
