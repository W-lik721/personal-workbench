# -*- coding: utf-8 -*-
"""每日 AI 日报自动更新（计划任务 WorkbenchAiDaily 每天 08:30 调用）。

流程：fetch_ai_daily.py 抓资讯 → export_data.py 重生成 data.json → 走
GitHub Contents API 推送（统一入口，2026-08-18 改造）。

为什么统一走 API 而不是 git：
  旧版用 git add/commit/pull --rebase/push，但本机 git 的 credential.helper
  是 Git Credential Manager，后台/计划任务环境无交互终端，GCM 无法弹窗
  授权，git push 必然失败（实测 rc=128 "could not read Password"）。
  GitHub Contents API + GITHUB_TOKEN 无交互依赖，是唯一长期实测成功的
  推送通道（sync.py 已在用）。本脚本对齐同一通道，消除「git vs API」
  双通道并发写 data.json 的冲突。

为什么用 Python 而不是 .cmd：
  cmd.exe 走 GBK 代码页，含中文的 UTF-8 批处理会直接崩（实测退出码
  -1073741510 / 0xC000013A，脚本第一行都没执行）。Python 无此问题，
  且能统一处理超时、日志、异常。
"""
import os
import subprocess
import sys
from datetime import datetime

from sync import push_file

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
LOG = os.path.join(HERE, "daily_ai.log")

ENV = dict(os.environ)
ENV["PYTHONIOENCODING"] = "utf-8"


def run(cmd, allow_fail=False, timeout=180):
    try:
        p = subprocess.run(cmd, cwd=HERE, env=ENV, capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=timeout)
        out = (p.stdout or "") + (p.stderr or "")
        return p.returncode, out.strip()
    except Exception as e:
        if allow_fail:
            return -1, "EXC %s" % e
        raise


def write_log(lines):
    text = "\n".join(lines)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    try:
        print(text)
    except UnicodeEncodeError:
        fallback = text.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(
            sys.stdout.encoding or "utf-8")
        print(fallback)


def main():
    lines = ["==== run %s ====" % datetime.now().strftime("%Y-%m-%d %H:%M:%S")]
    token = os.environ.get("GITHUB_TOKEN")
    lines.append("[GITHUB_TOKEN] %s" % ("存在" if token else "缺失"))
    if not token:
        lines.append("==== done TOKEN_MISSING ====")
        write_log(lines)
        return 1

    export_ok = True
    for script in ("fetch_ai_daily.py", "export_data.py"):
        rc, out = run([PY, script], allow_fail=True)
        lines.append("[%s] rc=%s\n%s" % (script, rc, out))
        if rc != 0:
            export_ok = False

    # API 推送：先推 ai_daily.json（日报数据，抓取失败则文件不存在时跳过）
    push_ok = True
    if os.path.exists(os.path.join(HERE, "ai_daily.json")):
        ok1 = push_file(token, "ai_daily.json",
                        "chore: AI 日报自动更新 %s" % datetime.now().strftime("%Y-%m-%d"))
        lines.append("[push ai_daily.json] %s" % ok1)
        push_ok = push_ok and ok1
    else:
        lines.append("[push ai_daily.json] 跳过（文件不存在，抓取可能失败）")
        push_ok = False

    ok2 = push_file(token, "data.json",
                    "chore: auto-sync data %s" % datetime.now().strftime("%Y-%m-%dT%H:%M:%S"))
    lines.append("[push data.json] %s" % ok2)
    push_ok = push_ok and ok2

    # 把同步健康度写进 data.json，再推一次（让面板能显示失败/陈旧告警）
    from sync_status import write_sync_status
    data_path = os.path.join(HERE, "data.json")
    st = write_sync_status(data_path, ok=(export_ok and push_ok))
    lines.append("[sync status] %s" % st)
    ok3 = push_file(token, "data.json", "chore: update sync health status")
    lines.append("[push health status] %s" % ok3)
    push_ok = push_ok and ok3

    lines.append("==== done %s ====" % ("OK" if push_ok else "FAIL"))
    write_log(lines)
    return 0 if push_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
