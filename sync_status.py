# -*- coding: utf-8 -*-
"""把『同步健康度』写入 data.json，供前端显示数据新鲜度与失败告警。

由 sync.py / daily_ai.py 在生成 data.json 后调用。
前端读 data.sync 字段：lastRun(ISO) / status(ok|fail) / nextRun(ISO) /
intervalHours / staleHours。
"""
import json
from datetime import datetime, timedelta

# 自动同步节奏：WorkbenchAutoSync 每小时一次
INTERVAL_HOURS = 1
# 超过这个时间没成功同步就判为「陈旧」，前端标红告警
STALE_HOURS = 2


def write_sync_status(data_path, ok, interval_hours=INTERVAL_HOURS, stale_hours=STALE_HOURS):
    """在 data.json 中注入 sync 字段；ok=本次同步（含 git push）是否成功。"""
    try:
        with open(data_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    now = datetime.now()
    next_run = now + timedelta(hours=interval_hours)
    data["sync"] = {
        "lastRun": now.strftime("%Y-%m-%dT%H:%M:%S"),
        "status": "ok" if ok else "fail",
        "nextRun": next_run.strftime("%Y-%m-%dT%H:%M:%S"),
        "intervalHours": interval_hours,
        "staleHours": stale_hours,
    }
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return data.get("sync")
