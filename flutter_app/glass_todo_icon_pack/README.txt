Glass-ToDo 图标包（自动生成）
=========================

包含：
1) assets/icon.png        —— 彩色 App 图标源图（可给 flutter_launcher_icons 用）
2) assets/icon_fg.png     —— Adaptive Icon 前景（透明）
3) assets/icon_bg.png     —— Adaptive Icon 背景（纯色）
4) android_notification_icon/drawable-*/ic_notify.png —— Android 通知 small icon（白色透明单色）

快速用法：
A) 替换桌面图标（Launcher Icon）
- 把 assets/icon.png / icon_fg.png 放进你 Flutter 项目的 assets/ 目录
- pubspec.yaml 添加：
  dev_dependencies:
    flutter_launcher_icons: ^0.13.1
  flutter_icons:
    android: true
    image_path: "assets/icon.png"
    adaptive_icon_background: "#40605F"
    adaptive_icon_foreground: "assets/icon_fg.png"
- 运行：
    flutter pub get
    dart run flutter_launcher_icons
    flutter clean
  并建议卸载旧 App 后重新安装（避免图标缓存）

B) 替换通知图标（你截图圈出来那块）
- 把 android_notification_icon 里各个 drawable-* 文件夹复制到：
  android/app/src/main/res/
- 在你用的通知/前台服务插件里，把 small icon 指向 ic_notify
  （参数名可能叫 icon / notificationIcon / setSmallIcon 等）
