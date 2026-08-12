import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite_workbench/services/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Store 本地存储', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    test('待办读写', () {
      Store.saveTodos([Todo('买牛奶'), Todo('写周报', done: true)]);
      final l = Store.todos();
      expect(l.length, 2);
      expect(l[0].text, '买牛奶');
      expect(l[1].done, true);
    });

    test('速记/收藏/入口/课程表读写', () {
      Store.saveNotes([Note('灵感一闪', 1700000000000)]);
      expect(Store.notes().length, 1);
      Store.saveFavs([Fav('标题', 'https://x', '源', 1700000000000)]);
      expect(Store.favs()[0].title, '标题');
      Store.saveLinks([Link('抖音', 'https://douyin.com')]);
      expect(Store.links()[0].label, '抖音');
      Store.saveCourses([Course(name: '高数', time: '08:00')]);
      expect(Store.courses()[0].name, '高数');
    });

    test('AI 记忆读写（长期记忆）', () {
      Store.saveAiMemory(['用户喜欢简洁回答']);
      expect(Store.aiMemory(), ['用户喜欢简洁回答']);
      Store.saveAiMemory([]);
      expect(Store.aiMemory(), isEmpty);
    });

    test('对话历史读写', () {
      Store.saveAiHistory([
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好呀'},
      ]);
      final h = Store.aiHistory();
      expect(h.length, 2);
      expect(h[0]['role'], 'user');
      expect(h[1]['content'], '你好呀');
    });

    test('记忆开关与条数默认值', () {
      expect(Store.aiMemoryOn, true); // 默认开
      Store.aiMemoryOn = false;
      expect(Store.aiMemoryOn, false);
      expect(Store.aiMemoryMax, 20); // 默认 20 条
    });

    test('对话携带长期记忆只取最近 15 条', () {
      final many = List.generate(30, (i) => '记忆$i');
      Store.saveAiMemory(many);
      final chat = Store.aiMemoryForChat();
      expect(chat.length, Store.aiMemoryChatMax);
      expect(chat.first, '记忆15'); // 最新在末尾，取末尾 15 条
      expect(chat.last, '记忆29');
    });

    test('长期记忆少于上限时全量返回', () {
      Store.saveAiMemory(['a', 'b']);
      expect(Store.aiMemoryForChat(), ['a', 'b']);
    });

    test('清空所有数据：清内容、保留设置', () {
      Store.saveTodos([Todo('x')]);
      Store.saveNotes([Note('n', 1)]);
      Store.saveFavs([Fav('f', 'u', 's', 1)]);
      Store.saveLinks([Link('l', 'u')]);
      Store.saveCourses([Course(name: 'c')]);
      Store.saveAiHistory([{'role': 'user', 'content': 'hi'}]);
      Store.saveAiMemory(['m']);
      Store.aiMemoryOn = false;
      Store.aiMemoryMax = 10;
      Store.resetAllData();
      expect(Store.todos(), isEmpty);
      expect(Store.notes(), isEmpty);
      expect(Store.favs(), isEmpty);
      expect(Store.links(), isEmpty);
      expect(Store.courses(), isEmpty);
      expect(Store.aiHistory(), isEmpty);
      expect(Store.aiMemory(), isEmpty);
      expect(Store.aiMemoryOn, false); // 设置保留
      expect(Store.aiMemoryMax, 10);
    });

    test('日报/新闻缓存字段', () {
      Store.cacheReportJson = '{"date":"2026-08-10"}';
      Store.cacheReportAt = 12345;
      Store.cacheDnewsJson = '{"data":{}}';
      expect(Store.cacheReportJson, contains('2026-08-10'));
      expect(Store.cacheReportAt, 12345);
      expect(Store.cacheDnewsJson, contains('data'));
    });
  });

  group('Api 数据解析', () {
    test('AI 日报解析', () {
      const body = '{"date":"2026-08-10","generatedAt":"2026-08-10T08:00:00Z",'
          '"sections":[{"label":"模型","items":[{"title":"新闻A","summary":"摘要","source":"源","url":"http://x"}]}]}';
      final r = Api.parseDailyReport(body);
      expect(r.date, '2026-08-10');
      expect(r.count, 1);
      expect(r.sections[0].label, '模型');
      expect(r.sections[0].items[0].title, '新闻A');
      expect(r.sections[0].items[0].source, '源');
    });

    test('每日新闻解析', () {
      const body = '{"data":{"date":"2026-08-10","news":["新闻1","新闻2"],"note":"温馨提示"}}';
      final d = Api.parseDailyNews(body);
      expect(d.items.length, 2);
      expect(d.items[0].title, '新闻1');
      expect(d.tip, '温馨提示');
    });

    test('异常 JSON 不崩溃', () {
      expect(() => Api.parseDailyReport('not-json'), throwsA(anything));
      final empty = Api.parseDailyReport('{"date":"x"}');
      expect(empty.count, 0);
      expect(empty.sections, isEmpty);
    });
  });

  group('技术热榜多源解析', () {
    test('掘金源解析', () {
      const body = '{"source":"juejin","items":[{"article_info":{'
          '"article_id":"7201","title":"掘金文章A","brief_content":"摘要A",'
          '"article_url":"https://juejin.cn/post/7201","comment_count":3,"ctime":1700000000},'
          '"author_user_info":{"user_name":"作者A"},"tags":[{"tag_name":"前端"}]}]}';
      final list = Api.parseHot(body);
      expect(list.length, 1);
      expect(list[0].title, '掘金文章A');
      expect(list[0].url, 'https://juejin.cn/post/7201');
      expect(list[0].by, '作者A');
      expect(list[0].source, contains('前端'));
      expect(list[0].replies, 3);
      expect(Api.hotSource(body), 'juejin');
    });

    test('少数派源解析（url 自动补全）', () {
      const body = '{"source":"sspai","items":[{"id":123,"title":"少数派文章","summary":"摘要B",'
          '"created_at":1700000000,"comments_count":5,"category":{"title":"效率"},"user":{"name":"作者B"}}]}';
      final list = Api.parseHot(body);
      expect(list.length, 1);
      expect(list[0].title, '少数派文章');
      expect(list[0].url, 'https://sspai.com/post/123');
      expect(list[0].source, '效率');
      expect(list[0].by, '作者B');
      expect(list[0].replies, 5);
      expect(Api.hotSource(body), 'sspai');
    });

    test('V2EX 源解析（含 url 为空回退）', () {
      const body = '{"source":"v2ex","items":[{"id":1,"title":"V2EX帖子","url":"",'
          '"content":"内容","replies":9,"created":1700000000,"member":{"username":"u"}}]}';
      final list = Api.parseHot(body);
      expect(list.length, 1);
      expect(list[0].title, 'V2EX帖子');
      expect(list[0].url, 'https://www.v2ex.com/t/1'); // url 为空回退到帖子页
      expect(list[0].source, 'V2EX');
      expect(list[0].replies, 9);
    });

    test('旧版无 source 缓存按 V2EX 解析', () {
      const body = '{"items":[{"id":2,"title":"旧缓存帖","url":"https://www.v2ex.com/t/2","replies":1,"created":1700000000,"member":{"username":"u"}}]}';
      final list = Api.parseHot(body);
      expect(list.length, 1);
      expect(list[0].source, 'V2EX');
      expect(Api.hotSource(body), ''); // 旧缓存无 source
    });

    test('空 items 返回空列表不崩溃', () {
      expect(Api.parseHot('{"source":"juejin","items":[]}'), isEmpty);
    });
  });
}
