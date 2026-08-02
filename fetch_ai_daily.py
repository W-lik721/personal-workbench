# -*- coding: utf-8 -*-
"""抓取每日 AI 资讯，生成 ai_daily.json（供 export_data.py 合并进 data.json）。

数据源：https://aihot.virxact.com  公开匿名 REST API，无需 API Key。
  - /api/public/daily                       最新成品日报（UTC 整日切片）
  - /api/public/items?mode=selected&since=  近 24h 精选（补充日报之外的新条目）

设计要点：
  - 必须带浏览器 User-Agent，默认 curl/python UA 会被 nginx 黑名单 403。
  - 抓取失败时**不覆盖**已有 ai_daily.json，保留上一次成功的结果。
  - 按 title 去重，日报优先，精选补位；单节最多 8 条，总量最多 20 条。
"""
import os
import json
import ssl
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = "https://aihot.virxact.com"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ai_daily.json")

MAX_PER_SECTION = 8
MAX_TOTAL = 20

# aihot 的 5 个英文 category → 中文小节名（与日报成品的中文 label 对齐，便于合并同组）
CAT_ZH = {
    "ai-models": "模型发布",
    "ai-products": "产品发布",
    "industry": "行业动态",
    "paper": "论文研究",
    "tip": "技巧与观点",
}
# 展示顺序：重要的排前面
SEC_ORDER = ["模型发布", "产品发布", "行业动态", "论文研究", "技巧与观点", "快讯"]


def _get(path, timeout=25):
    url = BASE + path
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        # Windows 证书链偶发问题时降级（数据为公开只读资讯，可接受）
        ctx2 = ssl._create_unverified_context()
        with urllib.request.urlopen(req, timeout=timeout, context=ctx2) as r:
            return json.loads(r.read().decode("utf-8"))


def _norm(it, label):
    return {
        "title": (it.get("title") or "").strip(),
        "summary": (it.get("summary") or "").strip(),
        "url": it.get("sourceUrl") or it.get("permalink") or "",
        "source": it.get("sourceName") or "",
        "label": label,
    }


def fetch_daily():
    """成品日报，返回 (date, sections列表)"""
    d = _get("/api/public/daily")
    secs = []
    for s in d.get("sections") or []:
        label = s.get("label") or "其他"
        for it in (s.get("items") or []):
            secs.append(_norm(it, label))
    for it in (d.get("flashes") or []):
        secs.append(_norm(it, "快讯"))
    return d.get("date") or "", d.get("attribution", {}).get("canonical", ""), secs


def fetch_selected(hours=24):
    """近 N 小时精选，补充日报之外的新鲜条目"""
    since = (datetime.now(timezone.utc) - timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
    d = _get("/api/public/items?mode=selected&since=%s&take=40" % since)
    items = d.get("items") if isinstance(d, dict) else d
    out = []
    for it in (items or []):
        if not isinstance(it, dict):
            continue
        raw = str(it.get("category") or it.get("categoryLabel") or "精选")
        out.append(_norm(it, CAT_ZH.get(raw, raw)))
    return out


def build():
    date_s, canonical, items = "", "", []
    err = []
    try:
        date_s, canonical, items = fetch_daily()
    except Exception as e:
        err.append("daily: %s" % e)
    try:
        extra = fetch_selected(24)
    except Exception as e:
        extra = []
        err.append("selected: %s" % e)

    seen = set(i["title"] for i in items if i["title"])
    for it in extra:
        if len(items) >= MAX_TOTAL:
            break
        if it["title"] and it["title"] not in seen:
            seen.add(it["title"])
            items.append(it)

    if not items:
        raise RuntimeError("没有抓到任何条目；" + " | ".join(err))

    # 按 label 归组，每组截断
    order, groups = [], {}
    for it in items:
        lb = CAT_ZH.get(it["label"], it["label"]) or "其他"
        if lb not in groups:
            groups[lb] = []
            order.append(lb)
        if len(groups[lb]) < MAX_PER_SECTION:
            groups[lb].append({k: it[k] for k in ("title", "summary", "url", "source")})
    # 重要小节排前面，未知小节按出现顺序追加在后
    order.sort(key=lambda x: SEC_ORDER.index(x) if x in SEC_ORDER else 99)

    return {
        "date": date_s or datetime.now().strftime("%Y-%m-%d"),
        "fetchedAt": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "source": "AI HOT",
        "canonical": canonical or (BASE + "/daily"),
        "count": sum(len(v) for v in groups.values()),
        "sections": [{"label": lb, "items": groups[lb]} for lb in order],
        "warnings": err,
    }


def main():
    try:
        data = build()
    except Exception as e:
        print("[WARN] AI 日报抓取失败，保留上一次结果：%s" % e)
        if os.path.isfile(OUT):
            print("       已有 %s，未覆盖" % OUT)
        return 1
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("[OK] AI 日报 %s · %d 条 · %d 节 -> %s"
          % (data["date"], data["count"], len(data["sections"]), OUT))
    for s in data["sections"]:
        print("   - %s (%d)" % (s["label"], len(s["items"])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
