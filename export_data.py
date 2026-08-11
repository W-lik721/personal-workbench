# -*- coding: utf-8 -*-
"""从本机 WorkBuddy 真实数据源抓取，生成 data.json（双端工作台用）。

数据源：
- skills : 扫描 ~/.workbuddy/skills/*/SKILL.md
- 自动化 : workbuddy.db -> automations
- 模型   : ~/.workbuddy/models.json
- 记忆   : 工作区 .workbuddy/memory/ 文件数
- 会话   : workbuddy.db -> sessions（近期 + 近17周热力图）
- 知识库 : 工作区 knowledge-base/ + vault/
- 磁盘   : ctypes GetDiskFreeSpaceExW
- MCP    : ~/.workbuddy/mcp.json
"""
import os
import json
import sqlite3
import ctypes
import subprocess
import time
from datetime import datetime, date, timedelta

WB = r"C:\Users\13115\.workbuddy"
WS = r"D:\Users\qingdeng-ws"
SKILLS_DIR = os.path.join(WB, "skills")
DB = os.path.join(WB, "workbuddy.db")
MODELS = os.path.join(WB, "models.json")
MCP = os.path.join(WB, "mcp.json")
MEM_DIR = os.path.join(WS, ".workbuddy", "memory")
WS_SKILLS = os.path.join(WS, ".workbuddy", "skills")
KB_DIRS = [os.path.join(WS, "knowledge-base"), os.path.join(WS, "vault")]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.json")


def fm(path):
    try:
        t = open(path, encoding="utf-8").read()
    except Exception:
        return {}
    if not t.startswith("---"):
        return {}
    end = t.find("\n---", 3)
    if end < 0:
        return {}
    m = {}
    for ln in t[3:end].splitlines():
        if ":" in ln:
            k, v = ln.split(":", 1)
            m[k.strip()] = v.strip()
    return m


def get_skills():
    out = []
    if os.path.isdir(SKILLS_DIR):
        for n in sorted(os.listdir(SKILLS_DIR)):
            sp = os.path.join(SKILLS_DIR, n)
            if not os.path.isdir(sp):
                continue
            sk = os.path.join(sp, "SKILL.md")
            if not os.path.isfile(sk):
                continue
            d = fm(sk)
            out.append({
                "name": d.get("name", n),
                "desc": d.get("description", ""),
                "category": d.get("category", "通用能力"),
                "cmd": "打开工作台后调用 skill：%s" % n,
            })
    return out


def get_automations():
    out = []
    try:
        con = sqlite3.connect(DB)
        cur = con.cursor()
        cur.execute("PRAGMA table_info(automations)")
        cols = [c[1] for c in cur.fetchall()]
        cur.execute("SELECT * FROM automations WHERE deleted_at IS NULL")
        for row in cur.fetchall():
            d = dict(zip(cols, row))
            name = d.get("name", "")
            nxt = d.get("next_run_at") or d.get("next_run") or d.get("scheduled_at")
            cron = d.get("cron") or d.get("rrule") or ""
            status = d.get("status", "")
            nxt_text = ""
            if nxt:
                try:
                    iv = int(nxt)
                    if iv > 1e12:  # 毫秒
                        iv = iv / 1000
                    dt = datetime.fromtimestamp(iv)
                    nxt_text = dt.strftime("%m-%d %H:%M")
                except Exception:
                    nxt_text = str(nxt)
            out.append({"name": name, "status": status, "next": nxt_text, "cron": cron})
        con.close()
    except Exception as e:
        print("automations err", e)
    return out


def get_models():
    out = []
    try:
        d = json.load(open(MODELS, encoding="utf-8"))
        models_list = d if isinstance(d, list) else d.get("models", [])
        for m in models_list:
            if not isinstance(m, dict):
                continue
            url = m.get("url", "") or ""
            mid = m.get("id", "") or ""
            typ = "本机" if ("localhost" in url or "local" in mid.lower()) else "云端"
            out.append({"name": m.get("name", mid), "type": typ})
    except Exception as e:
        print("models err", e)
    return out


def get_local_models():
    return [m["name"] for m in get_models() if m["type"] == "本机"]


def get_ollama_models():
    """读取本机 Ollama 真实已装模型（ollama list）与运行中状态（ollama ps）。

    返回 {available, models:[{id,size,modified,tags:[name,...]}], running:[{name,size,processor}]}。
    与 status.localModels（WorkBuddy 接入配置）不同，这里取的是 Ollama 真正拉到本机的模型。
    """
    exe = r"C:\Users\13115\ollama\ollama.exe"
    out = {"available": False, "models": [], "running": []}
    if not os.path.isfile(exe):
        return out
    out["available"] = True
    try:
        r = subprocess.run([exe, "list"], capture_output=True, text=True, timeout=25)
        by_id = {}
        for ln in r.stdout.splitlines():
            s = ln.strip()
            if not s or s.startswith("NAME") or set(s) <= set("- "):
                continue
            parts = s.split()
            if len(parts) < 3:
                continue
            # 模型名不含空格（用 / : - _ .），故可安全 split
            # 同一 GGUF 文件在 Ollama 里可能有多个 tag（如短名 + 魔搭原生长名），
            # 第二列 ID 相同即同一模型，按 ID 去重并合并 tags，避免重复展示
            name = parts[0]
            mid = parts[1]
            size = (parts[2] + " " + parts[3]) if len(parts) > 3 else parts[2]
            modified = " ".join(parts[4:]) if len(parts) > 4 else ""
            if mid in by_id:
                if name not in by_id[mid]["tags"]:
                    by_id[mid]["tags"].append(name)
            else:
                by_id[mid] = {"id": mid, "size": size, "modified": modified, "tags": [name]}
        out["models"] = sorted(by_id.values(), key=lambda m: m["tags"][0])
    except Exception as e:
        print("ollama list err", e)
    try:
        r2 = subprocess.run([exe, "ps"], capture_output=True, text=True, timeout=25)
        for ln in r2.stdout.splitlines():
            s = ln.strip()
            if not s or s.startswith("NAME") or set(s) <= set("- "):
                continue
            parts = s.split()
            if not parts:
                continue
            out["running"].append({
                "name": parts[0],
                "size": (parts[2] + " " + parts[3]) if len(parts) > 3 else parts[2],
                "processor": parts[4] if len(parts) > 4 else "",
            })
    except Exception as e:
        print("ollama ps err", e)
    return out


def memory_count():
    try:
        return len([f for f in os.listdir(MEM_DIR) if os.path.isfile(os.path.join(MEM_DIR, f))])
    except Exception:
        return 0


def get_sessions():
    recent = []
    heat = {}
    try:
        con = sqlite3.connect(DB)
        cur = con.cursor()
        cur.execute("SELECT title, custom_title, status, updated_at, created_at FROM sessions "
                    "WHERE deleted_at IS NULL AND cwd LIKE ? ORDER BY updated_at DESC",
                    ("%%%s%%" % WS,))
        rows = cur.fetchall()
        today = date.today()
        start = today - timedelta(days=17 * 7 - 1)
        days = {}
        for i in range(17 * 7):
            days[(start + timedelta(days=i)).isoformat()] = []
        for title, custom_title, status, ua, ca in rows:
            # 优先显示 WorkBuddy 里的自定义会话名，没有时才用自动标题
            display = custom_title.strip() if custom_title else title
            if len(recent) < 15 and display:
                try:
                    dt = datetime.fromtimestamp(int(ua) / 1000)
                except Exception:
                    dt = None
                grp = "更早"
                if dt:
                    d0 = dt.date()
                    if d0 == today:
                        grp = "今天"
                    elif d0 == today - timedelta(days=1):
                        grp = "昨天"
                recent.append({
                    "title": title,
                    "customTitle": custom_title.strip() if custom_title else "",
                    "display": display,
                    "status": status,
                    "updated": dt.strftime("%m-%d %H:%M") if dt else "",
                    "group": grp,
                })
            # 热力图按活跃日归集会话标题（点击可看当天聊了啥），也用显示名
            try:
                d2 = datetime.fromtimestamp(int(ua) / 1000).date().isoformat()
                if d2 in days and display and display not in days[d2]:
                    days[d2].append(display)
            except Exception:
                pass
        heat = [{"date": k, "count": len(v), "titles": v[:8]} for k, v in sorted(days.items())]
        con.close()
    except Exception as e:
        print("sessions err", e)
        heat = []
    return recent, heat


def get_knowledge():
    files = []
    types = {}
    total = 0
    for kb in KB_DIRS:
        if not os.path.isdir(kb):
            continue
        for f in os.listdir(kb):
            fp = os.path.join(kb, f)
            if os.path.isfile(fp):
                total += 1
                e = os.path.splitext(f)[1].lower() or "(无扩展名)"
                types[e] = types.get(e, 0) + 1
                files.append({"name": f, "mtime": datetime.fromtimestamp(os.path.getmtime(fp)).strftime("%m-%d %H:%M")})
    files.sort(key=lambda x: x["mtime"], reverse=True)
    return {"total": total, "types": types, "files": files[:8]}


def get_disk():
    out = {}
    for drive in ("C:\\", "D:\\"):
        try:
            free = ctypes.c_ulonglong(0)
            total = ctypes.c_ulonglong(0)
            if ctypes.windll.kernel32.GetDiskFreeSpaceExW(drive, None, ctypes.byref(total), ctypes.byref(free)):
                out[drive[0]] = {"total": total.value // (1024 ** 3), "free": free.value // (1024 ** 3)}
        except Exception:
            pass
    return out


def get_weekly_changes():
    """聚合本周（近 7 天）本机发生的新增/变化，做成时间线。

    来源：
    - skills：扫描 user-level 与 workspace 的 skills/*/SKILL.md（mtime 本周内）
    - automations：workbuddy.db -> automations（created_at 本周内新建）
    - kb：knowledge-base/ + vault/ 新增文件（mtime 本周内）
    返回 [{kind, name, when(秒), scope?}]，按时间倒序；when 统一为秒级时间戳。
    """
    out = []
    now = time.time()
    window = 7 * 24 * 3600
    # 1) skills（user-level + 工作区）
    for base in (SKILLS_DIR, WS_SKILLS):
        if not os.path.isdir(base):
            continue
        for n in sorted(os.listdir(base)):
            sp = os.path.join(base, n)
            sk = os.path.join(sp, "SKILL.md")
            if not os.path.isfile(sk):
                continue
            mt = os.path.getmtime(sk)
            if now - mt <= window:
                scope = "本机" if base == SKILLS_DIR else "工作区"
                out.append({"kind": "skill", "name": n, "when": mt, "scope": scope})
    # 2) 自动化（本周新建）
    try:
        con = sqlite3.connect(DB)
        cur = con.cursor()
        cur.execute("PRAGMA table_info(automations)")
        cols = [c[1] for c in cur.fetchall()]
        ca = "created_at" if "created_at" in cols else None
        if ca:
            cur.execute("SELECT name, created_at FROM automations WHERE deleted_at IS NULL")
            for name, ts in cur.fetchall():
                if ts is None:
                    continue
                try:
                    mt = float(ts)
                except Exception:
                    continue
                if mt > 1e12:  # 毫秒
                    mt = mt / 1000
                if now - mt <= window:
                    out.append({"kind": "automation", "name": name or "(未命名)", "when": mt})
        con.close()
    except Exception as e:
        print("weekly automations err", e)
    # 3) 知识库新增文件
    for kb in KB_DIRS:
        if not os.path.isdir(kb):
            continue
        for f in sorted(os.listdir(kb)):
            fp = os.path.join(kb, f)
            if not os.path.isfile(fp):
                continue
            mt = os.path.getmtime(fp)
            if now - mt <= window:
                out.append({"kind": "kb", "name": f, "when": mt})
    out.sort(key=lambda x: x["when"], reverse=True)
    return out


def _probe_mcp_url(url, timeout=0.6):
    """探测 HTTP/streamableHttp 类 MCP 的本地端口是否可达，返回 True/False。"""
    import socket
    try:
        from urllib.parse import urlparse
        p = urlparse(url)
        host = p.hostname or "127.0.0.1"
        port = p.port or (443 if p.scheme == "https" else 80)
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except Exception:
        return False


def get_mcp():
    """返回 [{name, type, online}]；online 仅对 HTTP 类做端口探测，stdio 默认在线。

    disabled 的项直接跳过（不计入列表）。
    """
    try:
        servers = json.load(open(MCP, encoding="utf-8")).get("mcpServers", {})
    except Exception:
        return []
    out = []
    for name, cfg in servers.items():
        if not isinstance(cfg, dict):
            out.append({"name": name, "type": "stdio", "online": True})
            continue
        if cfg.get("disabled"):
            continue
        t = cfg.get("type", "stdio")
        if t in ("streamableHttp", "sse", "http") and cfg.get("url"):
            out.append({"name": name, "type": t, "online": _probe_mcp_url(cfg["url"])})
        else:
            out.append({"name": name, "type": t, "online": True})
    return out


def get_ai_daily():
    """读取 fetch_ai_daily.py 抓好的 ai_daily.json；并把历史日报累积进 history。

    历史随 data.json 一起经 sync.py 用 GitHub API 推送，天然持久化（无需额外文件/本地 git）。
    每次 export 时从「上一次生成的 data.json」恢复 history，upsert 当天，保留最近 14 天。
    """
    HERE = os.path.dirname(os.path.abspath(__file__))
    p = os.path.join(HERE, "ai_daily.json")
    try:
        d = json.load(open(p, encoding="utf-8"))
    except Exception:
        d = {"date": "", "fetchedAt": "", "count": 0, "sections": [],
             "canonical": "https://aihot.virxact.com/daily"}
    hist = []
    old = os.path.join(HERE, "data.json")
    if os.path.isfile(old):
        try:
            hist = (json.load(open(old, encoding="utf-8")).get("aiDaily") or {}).get("history", [])
        except Exception:
            hist = []
    if d.get("date"):
        hist = [h for h in hist if h.get("date") != d["date"]]
        hist.append({"date": d.get("date"), "fetchedAt": d.get("fetchedAt"),
                     "count": d.get("count"), "sections": d.get("sections"),
                     "canonical": d.get("canonical", "")})
        hist.sort(key=lambda x: x.get("date", ""), reverse=True)
        hist = hist[:14]
    d["history"] = hist
    return d


def get_daily_news():
    """读取 fetch_daily_news.py 抓好的 daily_news.json；并把历史累积进 history。

    与 get_ai_daily 同机制：每次 export 时从「上一次生成的 data.json」恢复 history，
    upsert 当天，保留最近 14 天，随 data.json 经 sync.py 推送天然持久化。
    """
    HERE = os.path.dirname(os.path.abspath(__file__))
    p = os.path.join(HERE, "daily_news.json")
    try:
        d = json.load(open(p, encoding="utf-8"))
    except Exception:
        d = {"date": "", "fetchedAt": "", "count": 0, "items": [],
             "source": "每日60秒 (vikiboss/60s)", "canonical": "https://github.com/vikiboss/60s",
             "tip": "", "cover": ""}
    hist = []
    old = os.path.join(HERE, "data.json")
    if os.path.isfile(old):
        try:
            hist = (json.load(open(old, encoding="utf-8")).get("dailyNews") or {}).get("history", [])
        except Exception:
            hist = []
    if d.get("date"):
        hist = [h for h in hist if h.get("date") != d["date"]]
        hist.append({"date": d.get("date"), "fetchedAt": d.get("fetchedAt"),
                     "count": d.get("count"), "items": d.get("items"),
                     "tip": d.get("tip", ""), "source": d.get("source", ""),
                     "canonical": d.get("canonical", "")})
        hist.sort(key=lambda x: x.get("date", ""), reverse=True)
        hist = hist[:14]
    d["history"] = hist
    return d


def main():
    sk = get_skills()
    autos = get_automations()
    mds = get_models()
    recent, heat = get_sessions()
    kb = get_knowledge()
    dsk = get_disk()
    mc = get_mcp()
    lm = get_local_models()
    ol = get_ollama_models()
    mem = memory_count()
    wk = get_weekly_changes()
    aid = get_ai_daily()
    dn = get_daily_news()
    now = datetime.now()

    # 技能使用统计：从会话标题反推每个 skill 的提及次数与最近使用日期
    titled = []
    for h in heat:
        for t in h.get("titles", []):
            titled.append((h["date"], t))
    today_iso = date.today().isoformat()
    for s in recent:
        titled.append((today_iso, s.get("title", "")))
    for s in sk:
        key = s["name"].lower()
        if key:
            s["usage"] = sum(1 for _, t in titled if key in t.lower())
            last = ""
            for d, t in sorted(titled, key=lambda x: x[0], reverse=True):
                if key in t.lower():
                    last = d
                    break
            s["lastUsed"] = last
        else:
            s["usage"] = 0
            s["lastUsed"] = ""

    guide = []
    if aid.get("count"):
        top = ""
        for s in aid.get("sections") or []:
            if s.get("items"):
                top = s["items"][0].get("title", "")
                break
        if top:
            guide.append("🗞️ 今日 AI 日报已更新（%d 条）：%s" % (aid["count"], top))
    if dn.get("count"):
        guide.append("📰 今日国内新闻已更新（%d 条），点「每日新闻」标签看看" % dn["count"])
    if autos:
        a = autos[0]
        if a["next"]:
            guide.append("⏰ 定时任务「%s」将于 %s 运行" % (a["name"], a["next"]))
        else:
            guide.append("定时任务「%s」已就绪" % a["name"])
    guide.append("用 prompt-forge 把今天的一个想法固化成可复用提示词")
    guide.append("挑一个「能力速达」里的 skill 今天实际用一次")

    quick = [
        {"icon": "🔄", "label": "刷新工作台", "cmd": "打开工作台（刷新面板）"},
        {"icon": "🎬", "label": "蒸馏视频", "cmd": "用 video-cangjie-distill 把以下视频转成 skill："},
        {"icon": "🗞️", "label": "AI 日报", "cmd": "生成今日 AI 日报（中文）：最新模型 / 工具 / 趋势"},
        {"icon": "📝", "label": "记待办", "cmd": "记一笔待办："},
        {"icon": "🔍", "label": "搜知识库", "cmd": "在 knowledge-base/ 搜索："},
        {"icon": "💡", "label": "给我灵感", "cmd": "根据我的工作台现状生成今日灵感：列出今日待办、知识库概况、已装 skill，给我 1-2 个今天可动手的小任务 + 一条 AI agent 学习路径 + 一个值得关注的 AI 趋势"},
        {"icon": "🧹", "label": "整理工作区", "cmd": "整理并精简工作区的 skill 与笔记"},
        {"icon": "📊", "label": "看状态", "cmd": "查看本机当前状态：已装模型 / 磁盘 / 定时任务"},
    ]

    data = {
        "generatedAt": now.strftime("%Y-%m-%d %H:%M"),
        "kpi": {
            "skills": len(sk), "automations": len(autos), "models": len(mds),
            "memory": mem, "knowledge": kb["total"], "sessions": len(recent),
        },
        "skills": sk,
        "quickActions": quick,
        "guide": guide,
        "status": {
            "skillsLastUpdate": now.strftime("%Y-%m-%d"),
            "automations": autos,
            "models": mds,
            "localModels": lm,
            "ollama": ol,
            "mcp": mc,
            "memoryLastUpdate": now.strftime("%Y-%m-%d"),
            "disk": dsk,
            "runtime": "3.13 / 22.22",
        },
        "sessions": {"recent": recent, "heatmap": heat},
        "knowledge": kb,
        "weekly": wk,
        "aiDaily": aid,
        "dailyNews": dn,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("✅ 已生成 data.json")
    print("   Skills : %d" % len(sk))
    print("   自动化 : %d" % len(autos))
    print("   模型   : %d (本机 %d)" % (len(mds), len(lm)))
    print("   记忆   : %d 个文件" % mem)
    print("   知识库 : %d 文件" % kb["total"])
    print("   会话   : 近期 %d / 热力图 %d 天" % (len(recent), len(heat)))
    print("   本周动态: %d 条" % len(wk))
    print("   磁盘   : C %s / D %s" % (dsk.get("C"), dsk.get("D")))
    print("   MCP    : %s" % mc)
    print("   AI日报 : %s · %d 条" % (aid.get("date") or "无", aid.get("count") or 0))
    print("   每日新闻: %s · %d 条" % (dn.get("date") or "无", dn.get("count") or 0))
    print("   输出   : %s" % OUT)


if __name__ == "__main__":
    main()
