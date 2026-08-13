import 'package:flutter_test/flutter_test.dart';
import 'package:lite_workbench/services/kb.dart';

void main() {
  group('Kb.search 知识库匹配', () {
    final idx = [
      {'path': '03-资源/计算机科学/Python入门.md', 'title': 'Python 入门', 'preview': '变量、循环、函数'},
      {'path': '03-资源/生活常识/理财避坑9条.md', 'title': '理财避坑 9 条', 'preview': '只用闲钱、不加杠杆'},
      {'path': '02-领域/健康/睡眠习惯.md', 'title': '睡眠习惯', 'preview': '早睡早起，连续打卡'},
      {'path': '05-数字分身/App记忆/2026-08-13-ai-memory.md', 'title': 'App AI 记忆快照', 'preview': '用户喜欢简洁回答'},
    ];

    test('命中标题关键词', () {
      final hits = Kb.search(idx, 'Python 怎么学');
      expect(hits.isNotEmpty, true);
      expect(hits.first['title'], 'Python 入门');
    });

    test('命中预览关键词', () {
      final hits = Kb.search(idx, '理财怎么避坑');
      expect(hits.first['title'], '理财避坑 9 条');
    });

    test('多词排序：命中越多的排越前', () {
      final hits = Kb.search(idx, '睡眠 打卡 早睡');
      expect(hits.first['title'], '睡眠习惯');
    });

    test('无匹配返回空', () {
      expect(Kb.search(idx, 'xyzabc 不存在的词'), isEmpty);
    });

    test('空索引不崩溃', () {
      expect(Kb.search([], '任意'), isEmpty);
    });
  });
}
