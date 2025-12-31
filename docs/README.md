# Glass Todo · Docs Site

本目录是一个“项目介绍网址”的静态站点（纯 HTML/CSS），首页用于宣传介绍，具体文档拆成多个独立页面，通过按钮/导航跳转。

## 本地预览

- 直接用浏览器打开：`docs/index.html`

## 页面结构

- `docs/index.html`：宣传首页
- `docs/quickstart.html`：开始使用（Docker / Windows）
- `docs/deploy.html`：部署说明（NAS / 反代 / Tunnel）
- `docs/config.html`：配置（环境变量）
- `docs/backup.html`：备份与恢复
- `docs/dev.html`：开发与构建
- `docs/faq.html`：常见问题

## 发布方式

### GitHub Pages

1) 仓库 Settings → Pages
2) Source 选择 `Deploy from a branch`
3) Branch 选择 `main`（或你的默认分支）
4) Folder 选择 `/docs`

> 已包含 `docs/.nojekyll`，避免 GitHub Pages 忽略下划线/特殊路径（同时也更“原样”）。

### 其它静态托管

把 `docs/` 目录作为静态站点目录发布即可（Nginx / Cloudflare Pages / NAS Web Station 等）。

## 自定义建议

- 首页文案与按钮：修改 `docs/index.html`
- Logo：替换 `docs/assets/logo.png`
- 颜色与布局：修改 `docs/assets/style.css`
