# Flutter 应用的 ProGuard/R8 规则（占位，Flutter 引擎与插件自带 consumer rules）
# 如需自定义混淆规则写在这里

# === ML Kit Text Recognition（拍照识题 OCR）===
# 只引入中文模型，但插件底层可能引用日文/韩文等语言选项类；
# R8 打包时会因找不到这些可选类而报错，用 -dontwarn 放行，
# -keep 防止已存在类被过度混淆。
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.android.gms.vision.**
