# Glass Todo（Flutter 客户端）

![Glass Todo logo](../logo.png)

本目录是 Glass Todo 的 Flutter 前端（Web / Android）。

- 项目总览与部署入口：`../README.md`
- Docker / Nginx / 备份脚本等：`../local_server/deploy/README.md`
- 项目介绍网址（静态文档站点）：`../docs/index.html`

## 开发

```bash
flutter pub get
flutter run -d chrome
```

## 构建

```bash
flutter build web --release
flutter build apk --release
```

## 发布 Web 到后端静态目录

后端会把 `local_server/public/` 作为站点目录对外提供；一键构建并发布 Web：

```powershell
cd ..\local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish_flutter_web.ps1
```
