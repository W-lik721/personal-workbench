// 数据模型 + 本地存储 + 网络 API（纯 Dart，无第三方 UI 依赖）
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// 跳转 AI tab 的全局桥：填问题 → 切到 AI tab（可选：选学习模式 + 直接发送）
// 由 AiPage 在 initState 注入（支持 mode / send）；main.dart 提供无参兜底版本
void Function(String text, {String mode, bool send})? aiAskGlobal;
// AI 页注册：填充输入框（配合 aiAskGlobal 使用）
void Function(String text)? aiFillGlobal;
// 设置页"清空对话历史"通知 AI 页同步清空的全局回调（由 AiPage 注册）
void Function()? aiClearGlobal;

// App 版本号：与 pubspec.yaml 的 version 字段保持同步（设置页"关于"展示用）
const String appVersion = '1.3.2+11';

// 由首页卡片跳转到指定 tab（学习中心等），由 MainShell 注入
void Function(int index)? switchTabGlobal;

// ---------- 模型 ----------
class Todo {
  String text;
  bool done;
  int? remindAt; // 可选提醒时间（毫秒时间戳），null = 不提醒
  Todo(this.text, {this.done = false, this.remindAt});
  Map<String, dynamic> toJson() => {'text': text, 'done': done, if (remindAt != null) 'remindAt': remindAt};
  Todo.fromJson(Map<String, dynamic> j)
      : text = j['text'] ?? '',
        done = j['done'] ?? false,
        remindAt = (j['remindAt'] is int) ? (j['remindAt'] as int) : null;
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

// 技术热榜条目（多源归一：掘金 / 少数派 / V2EX；source 为显示用来源名）
class HotItem {
  int id;
  String title, url, content, source, by;
  int replies, created;
  HotItem({this.id = 0, this.title = '', this.url = '', this.content = '', this.source = '', this.by = '', this.replies = 0, this.created = 0});
}

// 考试/假期倒计时事件（内置常用模板 + 自定义）
class ExamEvent {
  String name;
  int at; // 目标日期（毫秒时间戳，当天 00:00）
  String emoji; // 图标
  bool preset; // 是否来自内置模板（仅展示用，不影响逻辑）
  ExamEvent(this.name, this.at, {this.emoji = '📅', this.preset = false});
  Map<String, dynamic> toJson() => {'name': name, 'at': at, 'emoji': emoji, 'preset': preset};
  ExamEvent.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '',
        at = j['at'] ?? 0,
        emoji = j['emoji'] ?? '📅',
        preset = j['preset'] ?? false;
}

// 课程成绩（GPA / 加权平均分计算用）
class Grade {
  String name;
  double credit; // 学分
  double score; // 百分制分数
  Grade(this.name, this.credit, this.score);
  Map<String, dynamic> toJson() => {'name': name, 'credit': credit, 'score': score};
  Grade.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '',
        credit = (j['credit'] is num) ? (j['credit'] as num).toDouble() : 0,
        score = (j['score'] is num) ? (j['score'] as num).toDouble() : 0;
}

// 论文阶段进度（开题 → 初稿 → 查重 → 答辩）
class ThesisStage {
  String name;
  bool done;
  int? at; // 完成日期（毫秒），null = 未完成
  ThesisStage(this.name, {this.done = false, this.at});
  Map<String, dynamic> toJson() => {'name': name, 'done': done, if (at != null) 'at': at};
  ThesisStage.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '',
        done = j['done'] ?? false,
        at = (j['at'] is int) ? j['at'] : null;
}

// 闪卡（间隔重复复习用）
class Flashcard {
  String front; // 问题 / 正面
  String back; // 答案 / 背面
  int createdAt;
  int dueAt; // 下次复习到期（毫秒）
  int box; // 复习盒：0=新, 1=1天后, 2=3天后, 3=7天后
  Flashcard(this.front, this.back, {int? createdAt, int? dueAt, this.box = 0})
      : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        dueAt = dueAt ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toJson() => {'front': front, 'back': back, 'createdAt': createdAt, 'dueAt': dueAt, 'box': box};
  Flashcard.fromJson(Map<String, dynamic> j)
      : front = j['front'] ?? '',
        back = j['back'] ?? '',
        createdAt = j['createdAt'] ?? 0,
        dueAt = j['dueAt'] ?? 0,
        box = j['box'] ?? 0;
}

// 账号保管箱条目（存加密存储，不落明文 SharedPreferences）
class Account {
  String title; // 平台/站点名
  String username; // 账号/手机号
  String password;
  String note;
  Account(this.title, {this.username = '', this.password = '', this.note = ''});
  Map<String, dynamic> toJson() => {'title': title, 'username': username, 'password': password, 'note': note};
  Account.fromJson(Map<String, dynamic> j)
      : title = j['title'] ?? '',
        username = j['username'] ?? '',
        password = j['password'] ?? '',
        note = j['note'] ?? '';
}

// 心情日记（每日一句 + emoji，AI 周报用）
class Mood {
  String text;
  String emoji; // 心情图标
  int at; // 时间戳
  Mood(this.text, this.emoji, this.at);
  Map<String, dynamic> toJson() => {'text': text, 'emoji': emoji, 'at': at};
  Mood.fromJson(Map<String, dynamic> j)
      : text = j['text'] ?? '',
        emoji = j['emoji'] ?? '🙂',
        at = j['at'] ?? 0;
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

  // 考试/假期倒计时
  static List<ExamEvent> events() => _load('wb_events').map((j) => ExamEvent.fromJson(j)).toList();
  static void saveEvents(List<ExamEvent> l) => _save('wb_events', l.map((e) => e.toJson()).toList());
  // 内置常用模板（日期为常见参考，可改）：考研初试 / 四六级 / 寒暑假
  static List<ExamEvent> examPresets() {
    final y = DateTime.now().year;
    int d(int m, int day) => DateTime(y, m, day).millisecondsSinceEpoch;
    return [
      ExamEvent('🎓 考研初试', d(12, 19), emoji: '🎓', preset: true),
      ExamEvent('📚 英语四级(CET-4)', d(6, 13), emoji: '📚', preset: true),
      ExamEvent('📚 英语六级(CET-6)', d(12, 12), emoji: '📚', preset: true),
      ExamEvent('🌞 暑假', d(7, 1), emoji: '🌞', preset: true),
      ExamEvent('❄️ 寒假', d(1, 20), emoji: '❄️', preset: true),
    ];
  }

  // 成绩 / GPA
  static List<Grade> grades() => _load('wb_grades').map((j) => Grade.fromJson(j)).toList();
  static void saveGrades(List<Grade> l) => _save('wb_grades', l.map((g) => g.toJson()).toList());
  // GPA 绩点算法表：键=算法名，值=按分数下限降序的 [最低分, 绩点] 档（命中第一个 <= score 的档）
  static const Map<String, List<List<num>>> gpaAlgos = {
    '仰恩大学(4.0粗档)': [[90, 4.0], [80, 3.0], [70, 2.0], [60, 1.0], [0, 0.0]],
    '标准4.0(通用)': [[90, 4.0], [85, 3.7], [82, 3.3], [78, 3.0], [75, 2.7], [72, 2.3], [68, 2.0], [64, 1.5], [60, 1.0], [0, 0.0]],
    '浙大4.3': [[95, 4.3], [90, 4.0], [85, 3.7], [81, 3.3], [78, 3.0], [75, 2.7], [72, 2.3], [68, 2.0], [64, 1.5], [60, 1.0], [0, 0.0]],
  };
  // 选中的 GPA 算法（默认仰恩大学，用户为学校在读）
  static String get gpaAlgo => _p?.getString('wb_gpa_algo') ?? '仰恩大学(4.0粗档)';
  static set gpaAlgo(String v) => _p?.setString('wb_gpa_algo', v);
  // 百分制分数 → 绩点（按指定算法）
  static double scoreToGpaAlgo(String algo, double score) {
    if (algo == '5.0线性') {
      if (score < 60) return 0;
      return ((score - 50) / 10).clamp(0.0, 5.0);
    }
    final table = gpaAlgos[algo] ?? gpaAlgos['标准4.0(通用)']!;
    for (final row in table) {
      if (score >= row[0]) return row[1].toDouble();
    }
    return 0.0;
  }
  // 百分制分数 → 4.0 绩点（常见标准算法，兼容旧调用）
  static double scoreToGpa(double score) => scoreToGpaAlgo('标准4.0(通用)', score);
  // 加权平均分 + GPA（学分加权，按指定算法）
  static Map<String, double> computeGpa(List<Grade> grades, String algo) {
    double sumCredit = 0, wScore = 0, wGpa = 0;
    for (final g in grades) {
      sumCredit += g.credit;
      wScore += g.score * g.credit;
      wGpa += scoreToGpaAlgo(algo, g.score) * g.credit;
    }
    if (sumCredit == 0) return {'avg': 0, 'gpa': 0};
    return {'avg': wScore / sumCredit, 'gpa': wGpa / sumCredit};
  }

  // 论文阶段进度（首次进入给 4 个默认阶段）
  static List<ThesisStage> thesisStages() {
    final l = _load('wb_thesis');
    if (l.isEmpty) return [ThesisStage('开题'), ThesisStage('初稿'), ThesisStage('查重'), ThesisStage('答辩')];
    return l.map((j) => ThesisStage.fromJson(j)).toList();
  }
  static void saveThesis(List<ThesisStage> l) => _save('wb_thesis', l.map((s) => s.toJson()).toList());

  // 闪卡
  static List<Flashcard> cards() => _load('wb_cards').map((j) => Flashcard.fromJson(j)).toList();
  static void saveCards(List<Flashcard> l) => _save('wb_cards', l.map((c) => c.toJson()).toList());

  // 心情日记（普通存储；AI 周报用）
  static List<Mood> moods() => _load('wb_moods').map((j) => Mood.fromJson(j)).toList();
  static void saveMoods(List<Mood> l) => _save('wb_moods', l.map((m) => m.toJson()).toList());

  // 账号保管箱（存系统加密存储 Keystore/Keychain，不落明文）
  static Future<List<Account>> accounts() async {
    try {
      final s = await _sec.read(key: 'wb_accounts');
      if (s == null) return [];
      return (jsonDecode(s) as List).map((j) => Account.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }
  static Future<void> saveAccounts(List<Account> l) async {
    try {
      await _sec.write(key: 'wb_accounts', value: jsonEncode(l.map((a) => a.toJson()).toList()));
    } catch (_) {}
  }

  static bool get darkMode => _p?.getBool('wb_dark') ?? true;
  static set darkMode(bool v) => _p?.setBool('wb_dark', v);
  // 主题模式三态：system=跟随系统 / dark=深色 / light=浅色（默认深色，保持老用户习惯）
  static String get themeMode => _p?.getString('wb_theme_mode') ?? 'dark';
  static set themeMode(String v) => _p?.setString('wb_theme_mode', v);
  // 启动时自动云备份（需要已配 GitHub Token）
  static bool get autoSync => _p?.getBool('wb_auto_sync') ?? false;
  static set autoSync(bool v) => _p?.setBool('wb_auto_sync', v);
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

  // ---------- 云同步（GitHub 备份中转） ----------
  // 仓库名（owner/repo），默认用户自己的工作台仓库
  static String get syncRepo => _p?.getString('wb_sync_repo') ?? 'W-lik721/personal-workbench';
  static set syncRepo(String v) => _p?.setString('wb_sync_repo', v.trim().replaceAll(RegExp(r'^https?://[^/]+/'), '').replaceAll(RegExp(r'\.git$'), ''));
  // GitHub Personal Access Token：走加密存储，不落明文
  static Future<String> syncToken() async {
    try {
      return await _sec.read(key: 'wb_sync_token') ?? '';
    } catch (_) {
      return '';
    }
  }
  static Future<void> setSyncToken(String k) async {
    try {
      if (k.isEmpty) {
        await _sec.delete(key: 'wb_sync_token');
      } else {
        await _sec.write(key: 'wb_sync_token', value: k.trim());
      }
    } catch (_) {}
  }

  // ---------- 知识库（vault 中转，复用云同步 token 与 GitHub） ----------
  // 知识库仓库（默认用户 vault 的 GitHub 镜像 vault-backup）
  static String get kbRepo => _p?.getString('wb_kb_repo') ?? 'W-lik721/vault-backup';
  static set kbRepo(String v) => _p?.setString('wb_kb_repo', v.trim().replaceAll(RegExp(r'^https?://[^/]+/'), '').replaceAll(RegExp(r'\.git$'), ''));
  // 知识库分支（vault-backup 默认 master）
  static String get kbBranch => _p?.getString('wb_kb_branch') ?? 'master';
  static set kbBranch(String v) => _p?.setString('wb_kb_branch', v.trim().isEmpty ? 'master' : v.trim());
  // AI 助手「知识库问答」开关：开=发送时自动查知识库拼上下文
  static bool get kbOn => _p?.getBool('wb_kb_on') ?? true;
  static set kbOn(bool v) => _p?.setBool('wb_kb_on', v);

  // ---------- 日报/新闻缓存（原始 JSON + 抓取时间） ----------
  static String? get cacheReportJson => _p?.getString('wb_cache_report');
  static set cacheReportJson(String? v) => v == null ? _p?.remove('wb_cache_report') : _p?.setString('wb_cache_report', v);
  static int get cacheReportAt => _p?.getInt('wb_cache_report_at') ?? 0;
  static set cacheReportAt(int v) => _p?.setInt('wb_cache_report_at', v);
  static String? get cacheDnewsJson => _p?.getString('wb_cache_dnews');
  static set cacheDnewsJson(String? v) => v == null ? _p?.remove('wb_cache_dnews') : _p?.setString('wb_cache_dnews', v);
  static int get cacheDnewsAt => _p?.getInt('wb_cache_dnews_at') ?? 0;
  static set cacheDnewsAt(int v) => _p?.setInt('wb_cache_dnews_at', v);

  // 技术热榜缓存（V2EX 原始 JSON + 抓取时间）
  static String? get cacheHotJson => _p?.getString('wb_cache_hot');
  static set cacheHotJson(String? v) => v == null ? _p?.remove('wb_cache_hot') : _p?.setString('wb_cache_hot', v);
  static int get cacheHotAt => _p?.getInt('wb_cache_hot_at') ?? 0;
  static set cacheHotAt(int v) => _p?.setInt('wb_cache_hot_at', v);
  // 清掉旧版热榜缓存（升级时一次调用，避免坏数据闪烁）；新数据 fetchHotBody 会自动回填
  static Future<void> clearHotCache() async => _p?.remove('wb_cache_hot');

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
  // 对话时携带的长期记忆条数上限：存了几十条时不全带上，防止 prompt 撑爆
  static const int aiMemoryChatMax = 15;
  // 取最近 aiMemoryChatMax 条长期记忆（最新存的在末尾），供发消息时携带
  static List<String> aiMemoryForChat() {
    final m = aiMemory();
    return m.length > aiMemoryChatMax ? m.sublist(m.length - aiMemoryChatMax) : m;
  }
  // 记忆开关：关掉后不再保存新历史、发消息也不带记忆
  static bool get aiMemoryOn => _p?.getBool('wb_ai_memory_on') ?? true;
  static set aiMemoryOn(bool v) => _p?.setBool('wb_ai_memory_on', v);
  // 发送时携带的历史条数上限（消息条数，默认 20 = 最近 10 轮对话）
  static int get aiMemoryMax => _p?.getInt('wb_ai_memory_max') ?? 20;
  static set aiMemoryMax(int v) => _p?.setInt('wb_ai_memory_max', v);

  // ---------- 学习打卡（番茄钟时长累计 + 连续天数） ----------
  // 今日已学习秒数（番茄钟完成时累加）；连续打卡天数；上次学习日期（YYYY-MM-DD）
  static int get studySecondsToday => _p?.getInt('wb_study_sec') ?? 0;
  static set studySecondsToday(int v) => _p?.setInt('wb_study_sec', v);
  static int get studyStreak => _p?.getInt('wb_study_streak') ?? 0;
  static set studyStreak(int v) => _p?.setInt('wb_study_streak', v);
  static String get studyLastDate => _p?.getString('wb_study_last') ?? '';
  static set studyLastDate(String v) => _p?.setString('wb_study_last', v);

  // 番茄钟完成一次：累计时长 + 更新连续打卡（昨天学过→+1，否则重置为 1）
  static void addStudyMinutes(int minutes) {
    studySecondsToday = studySecondsToday + minutes * 60;
    final today = DateTime.now();
    final ds = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (studyLastDate == ds) return; // 今天已打过卡
    final yesterday = today.subtract(const Duration(days: 1));
    final ys = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    studyStreak = studyLastDate == ys ? studyStreak + 1 : 1;
    studyLastDate = ds;
  }

  // ---------- 备份与恢复（不含 API Key：避免明文落盘泄露） ----------
  // 导出的全部内容都是 SharedPreferences 里的本地数据，可用作"换机/误删"兜底
  static Map<String, dynamic> exportAll() => {
        'app': 'lite_workbench',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'data': {
          'wb_todos': todos().map((t) => t.toJson()).toList(),
          'wb_notes': notes().map((n) => n.toJson()).toList(),
          'wb_favs': favs().map((f) => f.toJson()).toList(),
          'wb_links': links().map((l) => l.toJson()).toList(),
          'wb_schedule': courses().map((c) => c.toJson()).toList(),
          'wb_events': events().map((e) => e.toJson()).toList(),
          'wb_grades': grades().map((g) => g.toJson()).toList(),
          'wb_thesis': thesisStages().map((s) => s.toJson()).toList(),
          'wb_cards': cards().map((c) => c.toJson()).toList(),
          'wb_ai_history': aiHistory(),
          'wb_ai_memory': aiMemory(),
          'wb_dark': darkMode,
          'wb_ai_prov': aiProv,
          'wb_ai_memory_on': aiMemoryOn,
          'wb_ai_memory_max': aiMemoryMax,
        }
      };

  // 从导出文件还原（只覆盖文件里有的字段，缺字段不动现有数据）。调用前需二次确认。
  static void importAll(Map<String, dynamic> m) {
    final data = ((m['data'] as Map?)?.cast<String, dynamic>()) ?? <String, dynamic>{};
    if (data['wb_todos'] != null) {
      saveTodos((data['wb_todos'] as List).map((j) => Todo.fromJson(j)).toList());
    }
    if (data['wb_notes'] != null) {
      saveNotes((data['wb_notes'] as List).map((j) => Note.fromJson(j)).toList());
    }
    if (data['wb_favs'] != null) {
      saveFavs((data['wb_favs'] as List).map((j) => Fav.fromJson(j)).toList());
    }
    if (data['wb_links'] != null) {
      saveLinks((data['wb_links'] as List).map((j) => Link.fromJson(j)).toList());
    }
    if (data['wb_schedule'] != null) {
      saveCourses((data['wb_schedule'] as List).map((j) => Course.fromJson(j)).toList());
    }
    if (data['wb_events'] != null) {
      saveEvents((data['wb_events'] as List).map((j) => ExamEvent.fromJson(j)).toList());
    }
    if (data['wb_grades'] != null) {
      saveGrades((data['wb_grades'] as List).map((j) => Grade.fromJson(j)).toList());
    }
    if (data['wb_thesis'] != null) {
      saveThesis((data['wb_thesis'] as List).map((j) => ThesisStage.fromJson(j)).toList());
    }
    if (data['wb_cards'] != null) {
      saveCards((data['wb_cards'] as List).map((j) => Flashcard.fromJson(j)).toList());
    }
    if (data['wb_ai_history'] != null) {
      saveAiHistory((data['wb_ai_history'] as List)
          .map((j) => (j as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList()
          .cast<Map<String, String>>());
    }
    if (data['wb_ai_memory'] != null) {
      saveAiMemory((data['wb_ai_memory'] as List).map((j) => j.toString()).toList());
    }
    if (data['wb_dark'] != null) darkMode = data['wb_dark'] as bool;
    if (data['wb_ai_prov'] != null) aiProv = data['wb_ai_prov'] as String;
    if (data['wb_ai_memory_on'] != null) aiMemoryOn = data['wb_ai_memory_on'] as bool;
    if (data['wb_ai_memory_max'] != null) aiMemoryMax = data['wb_ai_memory_max'] as int;
  }

  // 清空所有内容数据（待办/速记/收藏/入口/课程表/AI 历史/长期记忆）。
  // 保留：API Key（加密存储）、主题、AI 提供商与记忆开关等设置。
  // 调用方负责二次确认与通知 AI 页清空内存（aiClearGlobal）。
  static void resetAllData() {
    saveTodos([]);
    saveNotes([]);
    saveFavs([]);
    saveLinks([]);
    saveCourses([]);
    saveEvents([]);
    saveGrades([]);
    saveThesis([]);
    saveCards([]);
    saveAiHistory([]);
    saveAiMemory([]);
  }

  // 内存缓存：避免每次读写都全量 JSON 编解码（首页一个 _reload 会连 decode 4 遍，量大时明显卡）
  // _load 返回副本，调用方（如 Store.todos()..insert/..removeAt）原地改动不会污染缓存；
  // _save 同步刷新内存副本 + 落盘，保证内存与磁盘一致。
  static final Map<String, List<dynamic>> _mem = {};

  static List<dynamic> _load(String k) {
    try {
      final cached = _mem[k];
      if (cached != null) {
        return List<dynamic>.from(cached);
      }
      final s = _p?.getString(k);
      final v = s == null ? <dynamic>[] : (jsonDecode(s) as List);
      _mem[k] = List<dynamic>.from(v);
      return List<dynamic>.from(_mem[k]!);
    } catch (_) {
      return [];
    }
  }
  static void _save(String k, List<dynamic> v) {
    _mem[k] = List<dynamic>.from(v);
    _p?.setString(k, jsonEncode(v));
  }
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
    for (final s in secs) {
      count += s.items.length;
    }
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

  // 技术热榜：多源兜底（掘金 → 少数派 → V2EX），第一个能解析出条目的源胜出。
  // 返回统一包裹：{"source":"juejin|sspai|v2ex","items":[...],"fetchedAt":"..."}（items 为该源原始数组，便于缓存）
  static Future<String> fetchHotBody() async {
    Object? lastErr;
    for (final src in const ['juejin', 'sspai', 'v2ex']) {
      try {
        final raw = await _fetchHotSource(src);
        final wrapped = jsonEncode({
          'source': src,
          'items': raw,
          'fetchedAt': DateTime.now().toIso8601String(),
        });
        if (parseHot(wrapped).isNotEmpty) return wrapped; // 能解析出条目才算成功
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('技术热榜所有数据源都不可用${lastErr == null ? '' : '（$lastErr）'}');
  }

  // 读取热榜响应/缓存里的来源标识（旧版无 source 的缓存按 v2ex 处理）
  static String hotSource(String body) {
    try {
      return ((jsonDecode(body) as Map)['source'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  // 拉取指定源的原始条目数组；异常即抛，由 fetchHotBody 尝试下一源
  static Future<List<dynamic>> _fetchHotSource(String src) async {
    switch (src) {
      case 'juejin':
        final r = await http
            .post(
              Uri.parse('https://api.juejin.cn/recommend_api/v1/article/recommend_all_feed'),
              headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
              body: jsonEncode({'id_type': 2, 'client_type': 2608, 'sort_type': 200, 'cursor': '0', 'limit': 20}),
            )
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw Exception('掘金 HTTP ${r.statusCode}');
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (j['err_no'] != 0) throw Exception('掘金 err_no=${j['err_no']}');
        return j['data'] as List? ?? [];
      case 'sspai':
        final r = await http
            .get(
              Uri.parse('https://sspai.com/api/v1/article/index/page/get?limit=20&offset=0'),
              headers: {'User-Agent': _ua},
            )
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw Exception('少数派 HTTP ${r.statusCode}');
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        return j['data'] as List? ?? [];
      default: // v2ex
        final r = await http.get(Uri.parse('https://www.v2ex.com/api/topics/hot.json'),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw Exception('V2EX HTTP ${r.statusCode}');
        return jsonDecode(utf8.decode(r.bodyBytes)) as List;
    }
  }

  static List<HotItem> parseHot(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final src = (j['source'] ?? '').toString();
    return (j['items'] as List? ?? []).map((it) {
      final m = it as Map<String, dynamic>;
      if (src == 'juejin') return _hotFromJuejin(m);
      if (src == 'sspai') return _hotFromSspai(m);
      return _hotFromV2ex(m); // 默认 v2ex（含旧版无 source 缓存）
    }).toList();
  }

  // 数字转换：兼容 num / 字符串数字 / null（掘金返回的 ctime 是字符串）
  static int _num(dynamic v) {
    if (v is num) return v.toInt();
    final s = v?.toString().trim() ?? '';
    return int.tryParse(s) ?? 0;
  }

  // 时间戳统一转秒（兼容 ms/字符串），供页面 *1000 显示
  static int _normSec(dynamic v) {
    final n = _num(v);
    return n > 100000000000 ? n ~/ 1000 : n; // 毫秒级转秒
  }

  static HotItem _hotFromJuejin(Map<String, dynamic> m) {
    // 掘金 API 真实结构（已按公开文档/开源项目实测确认）：
    //   data[].item_info.article_info.{title, article_id, brief_content, url, ctime, comment_count}
    //   data[].item_info.author_user_info.user_name
    //   data[].item_info.tags[].tag_name
    // 回退链：item_info.article_info → article_info → item_info → 顶层
    final itemInfo = (m['item_info'] as Map? ?? {}).cast<String, dynamic>();
    final info = ((itemInfo['article_info'] ?? m['article_info']) as Map?)?.cast<String, dynamic>() ?? itemInfo;
    final author = ((itemInfo['author_user_info'] ?? m['author_user_info']) as Map? ?? {}).cast<String, dynamic>();
    final tags = (itemInfo['tags'] ?? m['tags']) as List? ?? const <dynamic>[];
    final firstTag = tags.isNotEmpty ? ((tags.first as Map)['tag_name']?.toString() ?? '') : '';
    final articleId = (info['article_id'] ?? info['id'] ?? '').toString();
    var url = (info['article_url'] ?? info['url'] ?? itemInfo['url'] ?? '').toString();
    if (url.isEmpty && articleId.isNotEmpty) url = 'https://juejin.cn/post/$articleId';
    return HotItem(
      id: int.tryParse(articleId) ?? 0,
      title: (info['title'] ?? info['article_title'] ?? itemInfo['title'] ?? m['title'] ?? '').toString(),
      url: url,
      content: (info['brief_content'] ?? info['brief'] ?? info['summary'] ?? info['content'] ?? itemInfo['brief_content'] ?? '').toString(),
      source: firstTag, // 顶部已显示"数据源 juejin"，这里只显示文章分类标签
      by: (author['user_name'] ?? author['name'] ?? '').toString(),
      replies: _num(info['comment_count'] ?? info['comments_count']),
      created: _normSec(info['ctime'] ?? info['created_at'] ?? itemInfo['ctime']),
    );
  }

  static HotItem _hotFromSspai(Map<String, dynamic> m) {
    final cat = (m['category'] as Map? ?? {}).cast<String, dynamic>();
    final user = (m['user'] as Map? ?? {}).cast<String, dynamic>();
    final id = _num(m['id']);
    return HotItem(
      id: id,
      title: m['title']?.toString() ?? '',
      url: id > 0 ? 'https://sspai.com/post/$id' : '',
      content: m['summary']?.toString() ?? '',
      source: (cat['title'] ?? '少数派').toString(),
      by: user['name']?.toString() ?? '',
      replies: _num(m['comments_count']),
      created: _normSec(m['created_at']),
    );
  }

  static HotItem _hotFromV2ex(Map<String, dynamic> m) {
    final member = (m['member'] as Map? ?? {}).cast<String, dynamic>();
    final id = _num(m['id']);
    final url = (m['url'] ?? '').toString();
    return HotItem(
      id: id,
      title: (m['title'] ?? '').toString(),
      url: url.isNotEmpty ? url : 'https://www.v2ex.com/t/$id',
      content: (m['content'] ?? '').toString(),
      source: 'V2EX',
      by: (member['username'] ?? '').toString(),
      replies: _num(m['replies']),
      created: _normSec(m['created']),
    );
  }

  // AI 助手：Agnes / 智谱
  static const aiProviders = {
    'agnes': {'label': 'Agnes 2.5 Flash', 'url': 'https://apihub.agnes-ai.cn/v1/chat/completions', 'model': 'agnes-2.5-flash'},
    'glm': {'label': '智谱 GLM Flash', 'url': 'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'model': 'glm-4-flash'},
  };

  // AI 学习模式：预设 system 提示词（空=通用助手）
  static const aiModes = {
    '': '',
    '解题讲解': '你现在是耐心的学习导师。用户给你题目/代码/概念时：先讲清思路（为什么），再给答案；用大白话，遇到常见错误（如变量名拼写、for 缩进）主动提醒。',
    '论文润色': '你现在是学术写作编辑。对用户的中英文论文/段落做润色：学术化表达、去掉口语与 AI 味、保持原意；输出润色后版本 + 简要说明改了哪里。',
    '期末重点': '你现在是备考教练。根据用户给的课程笔记/教材内容，提炼期末考试重点：核心概念、易考点、常见题型，输出结构化复习清单。',
    '作业检查': '你现在是作业批改老师。对用户粘贴的作业/代码：先指出错误和问题（含拼写/缩进等常见坑），再讲正确写法，最后给修改建议。',
    '翻译': '你现在是中英互译助手。中文→地道英文，英文→自然中文；保持专业术语准确，输出译文 + 必要的注释。',
  };

  static List<Map<String, String>> _buildMsgs(List<Map<String, String>> history, String question,
      {List<String> memory = const [], String kb = '', String mode = ''}) {
    final memBlock = memory.isEmpty
        ? ''
        : '\n\n【关于用户的长期记忆，对话时请自然运用这些信息】\n- ${memory.join('\n- ')}';
    final kbBlock = kb.isEmpty ? '' : '\n\n$kb';
    final modeBlock = mode.isEmpty ? '' : '\n\n$mode';
    return [
      {'role': 'system', 'content': '你是用户个人工作台的 AI 助手，用中文大白话回答，简洁、可操作。$modeBlock$memBlock$kbBlock'},
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
      {List<String> memory = const [], String kb = '', String mode = '', http.Client? client, required void Function(String chunk) onChunk}) async {
    final p = aiProviders[prov]!;
    final req = http.Request('POST', Uri.parse(p['url']!))
      ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer $key'})
      ..body = jsonEncode({
        'model': p['model'],
        'messages': _buildMsgs(history, question, memory: memory, kb: kb, mode: mode),
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
        final choices = (j['choices'] as List? ?? const <dynamic>[]);
        final delta = choices.isNotEmpty ? (choices[0] as Map)['delta'] as Map? : null;
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
    final choices = (j['choices'] as List? ?? const <dynamic>[]);
    final msg = choices.isNotEmpty ? (choices[0] as Map)['message'] as Map? : null;
    final content = msg?['content']?.toString().trim() ?? '';
    if (content.isNotEmpty) return content;
    final reasoning = msg?['reasoning_content']?.toString();
    if (reasoning != null && reasoning.isNotEmpty) return '（思考中：）\n$reasoning';
    return '（空回复）';
  }
}
