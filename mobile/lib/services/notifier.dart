// 本地通知服务：待办到点提醒（纯手机本地，无需联网/服务端）
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Notifier {
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static bool _tzReady = false;

  // 通知 id 范围：Android 限制为 32 位有符号整数，毫秒时间戳会溢出，用秒级取模
  static int _nid(int remindAtMs) => (remindAtMs ~/ 1000) % 2000000000;

  // 时区初始化只做一次（中国用户统一东八区）
  static void _ensureTz() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    _tzReady = true;
  }

  // App 启动时初始化（main 里调用一次）
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _p.initialize(settings: const InitializationSettings(android: android));
    // Android 13+ 需要在运行时申请通知权限
    await _p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // 通知权限当前是否已开
  static Future<bool> permission() async {
    final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ok = await a?.areNotificationsEnabled() ?? true;
    return ok;
  }

  // 安排一条待办提醒（重复调用会覆盖同 id 的旧通知）
  static Future<void> scheduleTodo(int remindAtMs, String text) async {
    final id = _nid(remindAtMs);
    await _p.cancel(id: id);
    _ensureTz();
    var when = DateTime.fromMillisecondsSinceEpoch(remindAtMs);
    final now = DateTime.now();
    if (!when.isAfter(now)) when = now.add(const Duration(minutes: 1));
    await _p.zonedSchedule(
      id: id,
      title: '⏰ 待办提醒',
      body: text,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_remind',
          '待办提醒',
          channelDescription: '待办事项到点提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // 取消一条待办提醒
  static Future<void> cancelTodo(int remindAtMs) => _p.cancel(id: _nid(remindAtMs));
}
