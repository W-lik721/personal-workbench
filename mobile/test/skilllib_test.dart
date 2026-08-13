import 'package:flutter_test/flutter_test.dart';
import 'package:lite_workbench/services/skilllib.dart';

void main() {
  group('SkillLib 分词与匹配', () {
    test('中文连续文本切出 2 字词（"怎么避坑"含"避坑"）', () {
      final w = SkillLib.wordSet('理财怎么避坑');
      expect(w.contains('理财'), true);
      expect(w.contains('避坑'), true);
    });

    test('英文整词保留、不产生单字噪音', () {
      final w = SkillLib.wordSet('Python 学习');
      expect(w.contains('Python'), true);
      expect(w.contains('Py'), false);
      expect(w.contains('学习'), true);
    });

    test('matchCount 按命中词计数', () {
      final w = SkillLib.wordSet('产品 设计 规划');
      expect(SkillLib.matchCount('产品经理方法论 设计', w), 2);
      expect(SkillLib.matchCount('没有相关', w), 0);
    });

    test('空查询不崩溃', () {
      expect(SkillLib.wordSet(''), isEmpty);
      expect(SkillLib.matchCount('任意文本', {}), 0);
    });
  });
}
