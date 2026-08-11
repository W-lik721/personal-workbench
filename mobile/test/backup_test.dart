// 备份/恢复（Store.exportAll / importAll）纯 Dart 单元测试：不依赖 widget、不碰真机
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite_workbench/services/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Store 备份与恢复', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.init();
    });

    test('exportAll 携带应用标识与全部数据字段', () {
      Store.saveTodos([Todo('待办A')]);
      Store.saveNotes([Note('速记A', 1)]);
      final m = Store.exportAll();
      expect(m['app'], 'lite_workbench');
      expect(m['data']['wb_todos'], isNotEmpty);
      expect(m['data']['wb_notes'], isNotEmpty);
      expect(m['data'], contains('wb_schedule'));
      expect(m['data'], contains('wb_ai_memory'));
      expect(m['data'], contains('wb_links'));
    });

    test('importAll 往返恢复（清空后导入应完整还原）', () {
      Store.saveTodos([Todo('买菜'), Todo('健身', done: true)]);
      Store.saveNotes([Note('想法', 123)]);
      Store.saveCourses([Course(name: '英语', time: '10:00', dow: '周一')]);
      final exported = Store.exportAll();

      // 模拟"清空本地 → 换新机/重装后导入"
      Store.saveTodos([]);
      Store.saveNotes([]);
      Store.saveCourses([]);
      expect(Store.todos(), isEmpty);

      Store.importAll(exported);
      expect(Store.todos().length, 2);
      expect(Store.todos()[1].done, true);
      expect(Store.notes()[0].text, '想法');
      expect(Store.courses()[0].name, '英语');
      expect(Store.courses()[0].dow, '周一');
    });

    test('importAll 只覆盖文件里有的字段（不误删其他数据）', () {
      Store.saveTodos([Todo('原始待办')]);
      Store.saveNotes([Note('原始速记', 1)]);
      // 只导入了 notes，不应动 todos
      Store.importAll({
        'app': 'lite_workbench',
        'data': {
          'wb_notes': [
            {'text': '新速记', 'at': 2}
          ],
        }
      });
      expect(Store.notes()[0].text, '新速记');
      expect(Store.todos().length, 1);
      expect(Store.todos()[0].text, '原始待办');
    });

    test('importAll 空 data 不报错、不污染现有数据', () {
      Store.saveTodos([Todo('保留')]);
      Store.importAll({'app': 'lite_workbench', 'data': {}});
      expect(Store.todos()[0].text, '保留');
    });
  });
}
