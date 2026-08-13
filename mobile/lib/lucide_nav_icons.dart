import 'package:flutter/material.dart';

/// 导航栏专用的 Lucide 图标（仅 7 个）。
///
/// 背景：官方 `lucide_icons` 包最新版（0.257.0）的 SDK 约束为 `<3.0.0`，
/// 与本项目的 Dart 3 环境不兼容、无法 `pub get`。故将 Lucide 开源字体
/// （MIT，lucide.dev，版本 0.257.0）作为本地字体内置，仅取导航栏所需的
/// 7 个字形，避免引入装不上的依赖。
///
/// 字形编码与 `lucide.ttf` 严格对应，勿随意改动。
class LucideNavIcons {
  static const String _family = 'Lucide';

  static const IconData home = IconData(0xf35e, fontFamily: _family);
  static const IconData newspaper = IconData(0xf40c, fontFamily: _family);
  static const IconData bot = IconData(0xf1c0, fontFamily: _family);
  static const IconData calendar = IconData(0xf1d2, fontFamily: _family);
  static const IconData graduationCap = IconData(0xf33e, fontFamily: _family);
  static const IconData wrench = IconData(0xf59d, fontFamily: _family);
  static const IconData settings = IconData(0xf4b9, fontFamily: _family);
}
