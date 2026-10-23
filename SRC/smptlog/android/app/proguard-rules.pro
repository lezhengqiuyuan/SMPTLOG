# Flutter 引擎与插件不需要额外保留规则；
# 这里只补 SQLite / FFI 与 JSON 反射相关的必要项。

-keep class org.sqlite.** { *; }
-keep class com.smptlog.app.** { *; }

# 保留 Dart 侧通过 FFI 调用的符号（Windows 不在 Android 生效，保留无害）
-dontwarn org.slf4j.**
