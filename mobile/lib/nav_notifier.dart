// 导航配置变更通知器（独立文件，避免 main ↔ boards ↔ custom_board 循环依赖）
// 设置页 / 自定义板块页改了底部导航或删除板块后调用，让主壳(MainShell)刷新。
import 'package:flutter/foundation.dart';

final navConfigNotifier = ValueNotifier<int>(0);
