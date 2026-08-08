# -*- coding: utf-8 -*-
"""抓取每日中文/国内新闻（「每日60秒读懂世界」开源 API），生成 daily_news.json。

数据源：https://github.com/vikiboss/60s  （公开、免 key）
  - 主：https://60s-api.viki.moe/v2/60s
  - 备：https://60s.viki.moe/v2/60s
  返回：data.date / data.news(头条列表) / data.tip(每日一言) / data.cover

设计要点（与 fetch_ai_daily.py 对齐）：
  - 必须带浏览器 User-Agent，否则偶发被拦。
  - 抓取失败时**不覆盖**已有 daily_news.json，保留上一次成功的结果。
  - 主域名失败时自动回退备用域名。
"""
import os
import json
import ssl
import urllib.request
from datetime import datetime

PRIMARY = "https://60s-api.viki.moe/v2/60s"
BACKUP = "https://60s.viki.moe/v2/60s"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "daily_news.json")


def _get(url, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        # 证书链偶发问题时降级（公开只读资讯，可接受）
        ctx2 = ssl._create_unverified_context()
        with urllib.request.urlopen(req, timeout=timeout, context=ctx2) as r:
            return json.loads(r.read().decode("utf-8"))


def fetch():
    """依次试主/备域名，返回解析后的 data 字典；都失败抛异常。"""
    last_err = None
    for url in (PRIMARY, BACKUP):
        try:
            d = _get(url)
            if not isinstance(d, dict):
                raise ValueError("返回非 JSON 对象")
            data = d.get("data")
            if not isinstance(data, dict) or not data.get("news"):
                raise ValueError("data.news 为空")
            return data
        except Exception as e:
            last_err = e
            print("  [try %s] 失败：%s" % (url, e))
    raise RuntimeError("所有域名都失败：" + str(last_err))


def build():
    data = fetch()
    news = [str(x).strip() for x in (data.get("news") or []) if str(x).strip()]
    items = [{"title": t, "summary": "", "url": "", "source": "每日60秒"} for t in news]
    return {
        "date": data.get("date") or datetime.now().strftime("%Y-%m-%d"),
        "fetchedAt": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "source": "每日60秒 (vikiboss/60s)",
        "canonical": "https://github.com/vikiboss/60s",
        "count": len(items),
        "items": items,
        "tip": (data.get("tip") or "").strip(),
        "cover": data.get("cover") or "",
        "warnings": [],
    }


def main():
    try:
        data = build()
    except Exception as e:
        print("[WARN] 每日新闻抓取失败，保留上一次结果：%s" % e)
        if os.path.isfile(OUT):
            print("       已有 %s，未覆盖" % OUT)
        return 1
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("[OK] 每日新闻 %s · %d 条 -> %s"
          % (data["date"], data["count"], OUT))
    for i, it in enumerate(data["items"][:5], 1):
        print("   %d. %s" % (i, it["title"][:40]))
    if data["tip"]:
        print("   一言：%s" % data["tip"][:40])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
