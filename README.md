# 个人工作台（双端 PWA）

一套代码、手机 + 电脑都能用的个人工作台。**深色主题、响应式、可"添加到主屏幕"当 App 用**，零后端、纯静态。

## 功能

- 顶部 KPI 指标条：Skills / 自动化 / 模型 / 记忆条目
- **能力速达**：本机能力卡片网格，点一下即复制调用指令；按实际使用频率排序并标 🔥
- **AI 日报**：每天 08:30 自动抓取当日 AI 资讯（模型/产品/行业/论文/技巧分栏），可直接点「让 AI 讲讲」
- **今日引导**：每日清单，会带上当天日报头条
- **状态看板**：自动化、模型、数据更新状态
- **我的速记**：随手记待办，纯浏览器本地存储，不上传
- **浅色/深色主题**：右上角一键切换，记住偏好
- 全局搜索、会话热力图（点格子看当天聊了啥）、立即刷新
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

## 部署（GitHub Pages，固定地址 + 自动同步）

- **线上地址（固定，推荐）**：https://w-lik721.github.io/personal-workbench/
- 仓库（公开）：https://github.com/W-lik721/personal-workbench
- 手机 / 电脑浏览器直接开；手机浏览器菜单「添加到主屏幕」即变成 App，离线也能开。
- **自动同步（核心）**：两个本机计划任务
  - `WorkbenchAutoSync` —— 每小时跑 `sync.cmd`，重抓本机真实数据 → `git push`。装了新 skill / 加了新自动化，最多 1 小时后线上更新。
  - `WorkbenchAiDaily` —— 每天 08:30 跑 `daily_ai.py`，抓当日 AI 资讯 → 重生成 data.json → `git push`。已开「错过则尽快补跑」「电池模式也跑」。
- 原理：`data.json` 已改为「永远走网络、不缓存」（见 sw.js）；两个任务都用本机 git 凭据（credential.helper=store）自动推送。
- 想立刻更新：双击 `sync.cmd`，或命令行 `python daily_ai.py`（含日报）。

### ⚠️ 改前端必做：bump 版本号
Service Worker 会缓存静态资源。**每次改 `styles.css` / `app.js` 后必须：**
1. `index.html` 里的 `?v=N` 加 1（如 `?v=7` → `?v=8`）
2. `sw.js` 里 `CACHE = "workbench-vN"` 加 1，`FILES` 列表的 `?v=N` 同步改

漏做的话用户端会一直吃旧缓存，看到「页面裸掉」（没样式）。另外 push 后要等 **30-50 秒** GitHub Pages 才构建完，别立刻 curl 验证。

### （备选）CloudStudio 静态快照
- 之前用 `cloudstudio-deploy` 部署过（链接形如 `https://<id>.sh4.agentos-app.net`）。**它是静态快照，需手动重部署才更新**，已主用 GitHub Pages，此方案仅作备份。
- 管理/删除已发布应用：WorkBuddy「设置 - 数据管理 - 我发布的应用」

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
├── export_data.py    # 从本机 WorkBuddy 抓取真实数据 → data.json
├── fetch_ai_daily.py # 抓 aihot 当日 AI 资讯 → ai_daily.json（零 API Key）
├── daily_ai.py       # 每日流程：抓日报 → 重生成 data.json → git push（计划任务 08:30 调）
├── ai_daily.json     # 当日 AI 日报数据
├── refresh.cmd       # 小白双击刷新（调用 export_data.py）
├── sync.cmd          # 每小时自动同步（含本机路径，已被 .gitignore 排除，不进公开仓库）
├── .gitignore        # 排除 sync.cmd / .env / *.log 等本机文件
└── README.md
```

> 为什么 `daily_ai.py` 是 Python 而不是 `.cmd`：cmd.exe 走 GBK 代码页，含中文的 UTF-8 批处理会直接崩溃（实测退出码 `-1073741510`，脚本第一行都跑不到）。Python 无此问题。

## 更新记录

### 2026-08-17 · 网页端 PWA 健壮性 & 交互打磨
- **防白屏（健壮性）**：新增 `normalizeData()` 兜底 `data.json` 缺字段（`kpi` / `status` / `skills` / `sessions` / `aiDaily` / `dailyNews` / `weekly` / `guide` / `knowledge` 等）；`render()` 包裹 `try/catch`，数据异常时显示友好错误卡而非整页空白。
- **弹窗统一（一致性）**：`aiClear` / `aiMemoryClear` 的原生 `confirm` 与 `aiSend` 无 Key 提示统一改为自定义 `WB.dialog`，风格一致且不被浏览器拦截。
- **交互增强（体验）**：新增快捷键 `/` 聚焦搜索框、`Esc` 关闭热力图详情；新增离线提示条（`offline` / `online` 事件 + 初始在线状态检测，复用 Service Worker 离线缓存）。
- **版本 bump（部署纪律）**：`index.html` `?v=62→63`、`sw.js` `CACHE workbench-v76→v77`（静态资源版本号三处一致，避免用户端吃旧缓存）。
