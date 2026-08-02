# 个人工作台（双端 PWA）

一套代码、手机 + 电脑都能用的个人工作台。**深色主题、响应式、可"添加到主屏幕"当 App 用**，零后端、纯静态。

## 功能

- 顶部 KPI 指标条：Skills / 自动化 / 模型 / 记忆条目
- **能力速达**：本机能力卡片网格，点一下即复制调用指令
- **今日引导**：可勾选的每日清单
- **状态看板**：自动化、模型、数据更新状态
- 手机竖屏单列、电脑宽屏双栏；离线可开（Service Worker 缓存）

## 本地预览

直接双击 `index.html` 即可看（此时用内置示例数据）。

要接真实数据或测试 PWA 安装，建议起一个本地服务器：

```bash
cd personal-workbench
python -m http.server 8080
# 浏览器打开 http://localhost:8080
```

> 手机预览同一局域网：电脑和手机连同一 WiFi，手机浏览器开 `http://<电脑内网IP>:8080`。

## 数据注入（接 WorkBuddy 真实数据）

面板默认读同目录下的 `data.json`。把 WorkBuddy 的 skills / 自动化 / 模型 / 记忆导出成如下结构即可：

```json
{
  "kpi": { "skills": 44, "automations": 3, "models": 6, "memory": 128 },
  "skills": [
    { "name": "技能名", "desc": "一句话说明", "cmd": "复制给 AI 的指令" }
  ],
  "guide": ["今日引导项 1", "今日引导项 2"],
  "status": {
    "skillsLastUpdate": "2026-08-02",
    "automations": [{ "name": "名称", "next": "下次时间" }],
    "models": [{ "name": "模型名", "type": "本机|云端" }],
    "memoryLastUpdate": "2026-08-02"
  }
}
```

## 接真实数据（一键刷新）

面板默认读同目录 `data.json`。已内置 `export_data.py`，自动从本机 WorkBuddy 抓取真实数据生成 `data.json`，覆盖示例：

- **Skills**：扫描 `C:\Users\13115\.workbuddy\skills\`，读取每个 SKILL.md 的 frontmatter（名称/描述）
- **自动化**：读 `C:\Users\13115\.workbuddy\workbuddy.db`，只取未删除的活跃任务，算下次运行时间
- **模型**：读 `C:\Users\13115\.workbuddy\models.json`，按 `localhost` 自动标记「本机/云端」
- **记忆**：统计 `D:\Users\qingdeng-ws\.workbuddy\memory\` 文件数
- **今日引导**：根据真实自动化动态生成

**运行方式**（二选一）：

```bash
# 方式 A：命令行
python export_data.py

# 方式 B：小白双击 refresh.cmd（已配好托管 Python 路径，跑完自动刷新）
```

跑完刷新浏览器，工作台即显示最新真实数据。

## 部署（免费静态托管，双端可用）

任选其一，推送整个文件夹即可：

- **CloudStudio（已部署）**：用 WorkBuddy 的 cloudstudio-deploy 一键上传整个文件夹，自动出 HTTPS 地址，手机电脑浏览器直接开。
  - 分享链接形如 `https://<id>.sh4.agentos-app.net`
  - ⚠️ 部署的是**静态快照**：`data.json` 是部署那一刻抓的真实数据。本地数据变了想更新线上 → 先双击 `refresh.cmd` 重新生成 `data.json`，再重新部署一次。
  - 管理/删除已发布应用：WorkBuddy「设置 - 数据管理 - 我发布的应用」
- **GitHub Pages**：仓库 Settings → Pages → 选分支根目录
- **Vercel / Netlify**：拖文件夹或连仓库，自动出 HTTPS 地址
- 部署后手机、电脑浏览器都能开；在手机浏览器菜单选「添加到主屏幕」即变成 App

## 文件结构

```
personal-workbench/
├── index.html      # 页面骨架
├── styles.css      # 深色主题 + 响应式
├── app.js          # 数据渲染 + PWA 注册 + 复制指令
├── data.json       # 数据（export_data.py 生成的真实数据）
├── manifest.json   # PWA 配置
├── sw.js           # Service Worker（离线/可安装）
├── icon.svg        # 图标
├── export_data.py  # 从本机 WorkBuddy 抓取真实数据 → data.json
├── refresh.cmd     # 小白双击刷新（调用 export_data.py）
└── README.md
```
