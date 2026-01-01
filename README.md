# Glass Todo

一个可自托管的轻量任务管理与专注工具（Todo / 日历 / 时间记录 / 番茄钟 / 统计）。

## [点击查看介绍](https://git.gemmm.top/index.html)

- 前端：Flutter（Web / Android）
- 后端：Node.js（Express）+ SQLite（单文件数据库）
- 静态站点：后端会把 `local_server/public/` 作为 Web 站点目录对外提供


## 快速开始

### 方式 A：Docker（推荐 NAS）

1) 进入部署目录：

```bash
cd local_server/deploy
```

2) 复制 Docker 配置并按需修改（端口/数据目录等）：

```bash
cp .env.docker.example .env.docker
# Windows 也可以用：copy .env.docker.example .env.docker
```

3) 启动：

```bash
docker compose --env-file .env.docker up -d
```

4) 验证：

```bash
curl http://127.0.0.1:${HOST_PORT:-3000}/health
```

### 方式 B：Windows 绿色启动（不依赖 Docker）

```powershell
cd local_server\deploy
copy .env.example .env
.\run.bat
```

## 构建并发布 Flutter Web（把前端发布到后端静态目录）

```powershell
cd local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish_flutter_web.ps1
```

## 项目结构

- `flutter_app/`：Flutter 客户端（Web / Android）
- `local_server/`：Node/Express 后端（SQLite + 附件）
- `local_server/deploy/`：Docker Compose、反代示例、备份恢复脚本

更多部署细节见：`local_server/deploy/README.md`。
