# -*- coding: utf-8 -*-
"""
个人工作台 —— 真实数据导出脚本
把本机 WorkBuddy 的 skills / 自动化 / 模型 / 记忆 抓出来，写成 data.json 喂给前端。
运行：python export_data.py  （或用 refresh.cmd 双击）
"""
import os
import json
import sqlite3
from datetime import datetime, timezone, timedelta

# ---- 路径（按本机实际情况）----
SKILLS_DIR = r"C:\Users\13115\.workbuddy\skills"
DB_PATH = r"C:\Users\13115\.workbuddy\workbuddy.db"
MODELS_JSON = r"C:\Users\13115\.workbuddy\models.json"
MEMORY_DIR = r"D:\Users\qingdeng-ws\.workbuddy\memory"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.json")


def fmt_ts(ms):
    """毫秒时间戳 -> 本地可读字符串"""
    if not ms:
        return None
    try:
        dt = datetime.fromtimestamp(ms / 1000)
        return dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return None


def fmt_day(ts):
    if not ts:
        return "-"
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def parse_frontmatter(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            text = f.read()
    except Exception:
        return {}
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            fm = text[3:end]
            data = {}
            for line in fm.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    data[k.strip()] = v.strip()
            return data
    return {}


def load_skills():
    skills = []
    if not os.path.isdir(SKILLS_DIR):
        return skills
    latest = 0
    for name in sorted(os.listdir(SKILLS_DIR)):
        d = os.path.join(SKILLS_DIR, name)
        if not os.path.isdir(d):
            continue
        skill_md = os.path.join(d, "SKILL.md")
        fm = parse_frontmatter(skill_md) if os.path.exists(skill_md) else {}
        title = fm.get("name") or name
        desc = fm.get("description") or "（暂无描述）"
        skills.append({"name": title, "desc": desc, "cmd": name})
        # 取最近修改时间
        try:
            m = os.path.getmtime(skill_md) if os.path.exists(skill_md) else os.path.getmtime(d)
            latest = max(latest, m)
        except Exception:
            pass
    return skills, latest


def load_models():
    models = []
    if not os.path.exists(MODELS_JSON):
        return models
    try:
        with open(MODELS_JSON, encoding="utf-8") as f:
            arr = json.load(f)
    except Exception:
        return models
    for m in arr:
        mid = m.get("id") or m.get("name") or "未知模型"
        url = (m.get("url") or "").lower()
        mtype = "本机" if ("local" in mid.lower() or "localhost" in url) else "云端"
        models.append({"name": mid, "type": mtype})
    return models


def load_automations():
    autos = []
    if not os.path.exists(DB_PATH):
        return autos
    try:
        con = sqlite3.connect(DB_PATH)
        cur = con.cursor()
        cur.execute(
            "SELECT id, name, status, schedule_type, next_run_at, last_run_at "
            "FROM automations WHERE deleted_at IS NULL"
        )
        rows = cur.fetchall()
        # 运行时状态
        running = {}
        try:
            cur.execute("SELECT automation_id, running FROM automation_runtime_state")
            for aid, r in cur.fetchall():
                running[aid] = bool(r)
        except Exception:
            pass
        con.close()
    except Exception:
        return autos

    for aid, name, status, stype, nxt, lst in rows:
        item = {"name": name}
        if running.get(aid):
            item["status"] = "运行中"
        elif status != "ACTIVE":
            item["status"] = "已暂停"
        else:
            nxt_s = fmt_ts(nxt)
            item["next"] = ("下次：" + nxt_s) if nxt_s else "待运行"
        autos.append(item)
    return autos


def load_memory():
    count = 0
    latest = 0
    if os.path.isdir(MEMORY_DIR):
        for fn in os.listdir(MEMORY_DIR):
            fp = os.path.join(MEMORY_DIR, fn)
            if os.path.isfile(fp):
                count += 1
                try:
                    latest = max(latest, os.path.getmtime(fp))
                except Exception:
                    pass
    return count, latest


def build_guide(autos):
    guide = []
    if autos:
        a0 = autos[0]
        when = a0.get("next") or a0.get("status") or ""
        guide.append(f"查看「{a0['name']}」{when}")
    guide.append("用 prompt-forge 把今天的一个想法固化成可复用提示词")
    guide.append("挑一个「能力速达」里的 skill 今天实际用一次")
    return guide[:4]


def main():
    skills, skills_mtime = load_skills()
    models = load_models()
    autos = load_automations()
    mem_count, mem_mtime = load_memory()

    data = {
        "kpi": {
            "skills": len(skills),
            "automations": len(autos),
            "models": len(models),
            "memory": mem_count,
        },
        "skills": skills,
        "guide": build_guide(autos),
        "status": {
            "skillsLastUpdate": fmt_day(skills_mtime) if skills_mtime else "-",
            "automations": autos,
            "models": models,
            "memoryLastUpdate": fmt_day(mem_mtime) if mem_mtime else "-",
        },
    }

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("✅ 已生成 data.json")
    print(f"   Skills : {len(skills)}")
    print(f"   自动化 : {len(autos)}")
    print(f"   模型   : {len(models)}")
    print(f"   记忆   : {mem_count} 个文件")
    print(f"   输出   : {OUT}")


if __name__ == "__main__":
    main()
