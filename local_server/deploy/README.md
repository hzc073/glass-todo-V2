# 后端部署需求与交付物（Windows 绿色启动 + Docker 正式部署）

项目基本信息：
- 服务：Node（Express）
- 默认端口：`3000`
- 数据库：PostgreSQL（推荐）/ SQLite（可选）
- 附件：本地目录保存
- 限制：单个附件最大 `50MB`（反代需要放开请求体大小）

本目录提供两种运行方式的“可直接复制使用”的交付物：Windows 一键启动脚本 + Docker Compose 部署 + Nginx 反代示例 + 备份恢复脚本。

---

## 1) 推荐目录结构

以 `local_server/` 作为后端根目录，推荐结构如下：

```
local_server/
  server.js
  package.json
  server/
  public/
  data/                      # 持久化数据（重启/升级不丢）
    postgres/                # PostgreSQL 数据目录（Docker Compose 默认）
    database.sqlite          # SQLite db 文件（当 DB_DRIVER=sqlite 时使用）
    attachments/             # 附件目录（可通过 ATTACHMENTS_DIR 修改）
  deploy/
    .env                     # 运行配置（从 .env.example 复制）
    docker-compose.yml
    run.bat                  # Windows 一键启动（调用 run.ps1）
    run.ps1
    nginx/
      glass-todo.conf        # Nginx 反代示例（含 HTTPS 片段）
    scripts/
      backup.ps1             # 备份（DB + 附件）
      restore.ps1            # 恢复（DB + 附件）
```

说明：
- `data/` 目录建议加入 `.gitignore`（避免把真实数据提交进仓库）。
- Docker 部署使用 bind mount：把宿主机 `local_server/data/` 挂载到容器 `/app/data/`。

---

## 2) 配置（.env）

复制一份配置：

```powershell
cd local_server\deploy
copy .env.example .env
```

关键配置项（至少）：
- `PORT`：Windows 绿色启动监听端口（默认 `3000`）
- `DB_DRIVER`：数据库类型（`postgres` / `sqlite`）
- `DATABASE_URL`：PostgreSQL 连接串（当 `DB_DRIVER=postgres` 时使用）
- `DB_PATH`：SQLite 文件路径（当 `DB_DRIVER=sqlite` 时使用，建议 `./data/database.sqlite`）
- `ATTACHMENTS_DIR`：附件目录（建议 `./data/attachments`）
- `CORS_ORIGINS`：允许访问的前端 Origin（逗号分隔；`*` 表示放开，正式环境不建议）
- `HOST_PORT`：Docker 映射到宿主机的端口（`HOST_PORT -> 容器 3000`）
- `IMAGE_TAG`：Docker 镜像 tag（版本号）

### Windows 一键 PostgreSQL（可选）

如果你不想在系统里安装 PostgreSQL，可以把 PostgreSQL（Windows binaries）放进仓库里，然后 `run.bat` 自动启动：

1) 解压 PostgreSQL 到 `local_server/bin/postgres/`（确保存在 `bin/postgres/bin/pg_ctl.exe`）
2) 修改 `deploy/.env`：
   - `DB_DRIVER=postgres`
   - `AUTO_START_POSTGRES=true`
   - `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`（以及可选的 `POSTGRES_PORT`）
3) 双击 `deploy/run.bat`

### Docker 专用配置（推荐）

为了避免 Windows 绿色启动与 Docker 配置互相干扰，建议 Docker 另用一份配置文件：

```powershell
cd local_server\deploy
copy .env.docker.example .env.docker
```

启动 Docker 时使用：

```bash
cd local_server/deploy
docker compose --env-file .env.docker up -d
```

---

## 3) A）Windows 绿色启动（不依赖 Docker）

### 3.1 从零开始启动

```powershell
cd local_server\deploy
.\run.bat
```

脚本会做以下事情：
- 读取 `deploy/.env` 并设置环境变量
- 确保 `local_server/data/` 与附件目录存在
- 如缺少依赖会执行 `npm install`
- 启动 `server.js`

### 3.2 验证服务是否正常

浏览器打开：
- `http://127.0.0.1:3000/health`

或命令行：

```powershell
curl http://127.0.0.1:3000/health
```

成功时返回 JSON，且 `ok: true`。

### 3.3 把 Flutter Web 接到后端（同一个端口 3000）

后端会把 `local_server/public/` 作为静态站点目录对外提供；因此你只要把 Flutter 的构建产物发布到这里即可。

一键发布（会执行 `flutter build web --release`，然后把 `flutter_app/build/web` 镜像到 `local_server/public`）：

```powershell
cd local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish_flutter_web.ps1
```

然后重启后端（重新运行 `run.bat`），访问：
- `http://127.0.0.1:3000/`

注意：
- 如果你在别的机器/手机上通过局域网访问（例如 `http://192.168.x.x:3000`），建议保持 `API_BASE_URL=` 为空，让前端使用“同源”调用后端（不依赖 `localhost`）。

### 3.4 备份与恢复（Windows）

强烈建议在备份/恢复前先停止服务（SQLite 模式下避免写入中导致文件不一致；PostgreSQL 模式建议用 `pg_dump` 在线备份）。

备份（生成目录或 zip）：

```powershell
cd local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup.ps1 -Zip
```

恢复（从某次备份目录或 zip 恢复）：

```powershell
cd local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -BackupPath ..\backups\backup_YYYYMMDD_HHMMSS
```

### 3.5 分发/打包（Windows 绿色版）

目标：给非开发用户分发一个“解压即用”的包（包含后端 + Flutter Web 静态资源 + 便携 Node 运行时），用户无需安装 Node/Flutter。

一键打包（会先发布 Flutter Web，再组装分发目录，并可选生成 zip）：

```powershell
cd local_server\deploy
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package_windows_portable.ps1 -Zip
```

输出位置（默认）：
- `release/GlassTodo-Portable-YYYYMMDD_HHMMSS/`
- `release/GlassTodo-Portable-YYYYMMDD_HHMMSS.zip`

分发给用户后：
1) 解压 zip
2) 双击 `run.bat`
3) 打开 `http://127.0.0.1:3000/`（端口在 `backend\\deploy\\.env` 修改）

升级建议：
- 用新版本包里的 `backend/` 覆盖旧版本的 `backend/`，保留原来的 `data/`（数据与附件都在这里）。

---

## 4) B）Docker 部署（正式环境）

### 4.1 一键启动（docker-compose）

```bash
cd local_server/deploy
cp .env.docker.example .env.docker
docker compose --env-file .env.docker up -d
```

端口映射规则：
- 容器内固定 `3000`
- 宿主机端口通过 `.env.docker` 的 `HOST_PORT` 控制，例如：
  - `HOST_PORT=8080` 表示 `8080 -> 3000`

### 4.2 验证服务是否正常（健康检查）

查看容器健康状态：

```bash
cd local_server/deploy
docker compose ps
```

直接请求健康接口：

```bash
curl http://127.0.0.1:${HOST_PORT:-3000}/health
```

### 4.3 数据持久化

`docker-compose.yml` 已把宿主机 `../data` 用于持久化，因此：
- PostgreSQL 数据：`local_server/data/postgres/`
- 附件：`local_server/data/attachments/`

### 4.4 日志查看与建议

查看实时日志：

```bash
cd local_server/deploy
docker compose logs -f --tail=200
```

已在 `docker-compose.yml` 中配置 Docker 日志滚动（避免无限增长占满磁盘）：
- `max-size: 10m`
- `max-file: 3`

### 4.5 备份与恢复（Docker）

由于使用的是宿主机目录持久化（bind mount），你可以选择：
- **停机备份**：`docker compose down` 后备份 `local_server/data/`（包含 `postgres/` 与 `attachments/`）
- **不停机备份**：使用 `pg_dump` 导出数据库 + 备份附件目录（更推荐）

建议流程（更安全）：

```bash
cd local_server/deploy
docker compose down
# 备份/恢复 local_server/data（例如复制或打包）
docker compose up -d
```

也可以直接使用本仓库提供的 PowerShell 脚本（在 Windows 服务器上）：
- `local_server/deploy/scripts/backup.ps1`
- `local_server/deploy/scripts/restore.ps1`

### 4.6 升级与回退（快速切换版本）

推荐做法：用镜像 tag 管理版本（通过 `.env` 的 `IMAGE_TAG`）。

升级：
1) 拉取/替换新版本代码（或切换到新分支/新 tag）
2) 修改 `local_server/deploy/.env`：设置新的 `IMAGE_TAG`（例如 `IMAGE_TAG=2025-12-30`）
3) 构建并滚动更新：

```bash
cd local_server/deploy
docker compose build --no-cache
docker compose up -d
docker compose ps
curl http://127.0.0.1:${HOST_PORT:-3000}/health
```

回退：
1) 把 `IMAGE_TAG` 改回旧值（或切回旧代码版本后重新 build）
2) 再执行：

```bash
cd local_server/deploy
docker compose up -d
```

---

## 5) 反向代理（Nginx 示例）

示例配置在：
- `local_server/deploy/nginx/glass-todo.conf`

要求覆盖点：
- 域名请求转发到后端端口（`proxy_pass http://127.0.0.1:8080;` 按实际修改）
- 支持 HTTPS（示例中给了证书路径占位）
- 支持大上传（已设置 `client_max_body_size 100m`，确保 >= 50MB 不会被拦截）

证书放置建议：
- 可使用 Let’s Encrypt / Certbot 自动签发
- 或把证书放到示例中的路径：
  - `/etc/nginx/certs/fullchain.pem`
  - `/etc/nginx/certs/privkey.pem`

---

## 6) 常见问题排查

- **端口被占用**
  - Windows：修改 `deploy/.env` 的 `PORT`
  - Docker：修改 `deploy/.env` 的 `HOST_PORT`
- **跨域失败（CORS）**
  - 配置 `CORS_ORIGINS` 为前端地址（逗号分隔），不要长期使用 `*`
- **上传大文件失败**
  - Nginx：确认 `client_max_body_size` >= `50m`
  - 反代/网关：确认没有更小的 body 限制
- **SQLite 模式备份不一致/恢复后报错**
  - SQLite：备份/恢复前先停服务（Windows 停止进程 / Docker `docker compose down`）
  - PostgreSQL：推荐使用 `pg_dump`/`pg_restore`（或停机备份 `data/postgres/`）
