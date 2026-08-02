# -*- coding: utf-8 -*-
"""每日 AI 日报自动更新（计划任务 WorkbenchAiDaily 每天 08:30 调用）。

流程：fetch_ai_daily.py 抓资讯 → export_data.py 重生成 data.json → git 提交推送。

为什么用 Python 而不是 .cmd：
  cmd.exe 走 GBK 代码页，含中文的 UTF-8 批处理会直接崩（实测退出码
  -1073741510 / 0xC000013A，脚本第一行都没执行）。Python 无此问题，
  且能统一处理超时、日志、异常。
"""
import os
import sys
import subprocess
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
LOG = os.path.join(HERE, "daily_ai.log")

ENV = dict(os.environ)
ENV["GIT_SSL_NO_VERIFY"] = "true"   # Windows Schannel 吊销检查会误伤，公开仓库可接受
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


def main():
    lines = ["==== run %s ====" % datetime.now().strftime("%Y-%m-%d %H:%M:%S")]

    for script in ("fetch_ai_daily.py", "export_data.py"):
        rc, out = run([PY, script], allow_fail=True)
        lines.append("[%s] rc=%s\n%s" % (script, rc, out))

    # 顺序很重要：先 add+commit，再 pull --rebase，最后 push。
    # 反过来（先 pull）会因工作区有未暂存改动直接 rc=128 中止。
    rc, out = run(["git", "add", "data.json", "ai_daily.json"], allow_fail=True)
    lines.append("[git add] rc=%s %s" % (rc, out))

    # 有改动才 commit（diff --cached --quiet 返回 1 表示暂存区有差异）
    rc, _ = run(["git", "diff", "--cached", "--quiet"], allow_fail=True)
    if rc != 0:
        rc2, out2 = run(["git", "commit", "-q", "-m",
                         "chore: AI 日报自动更新 %s" % datetime.now().strftime("%Y-%m-%d")],
                        allow_fail=True)
        lines.append("[git commit] rc=%s %s" % (rc2, out2))
        rc3, out3 = run(["git", "pull", "--rebase", "-q"], allow_fail=True)
        lines.append("[git pull --rebase] rc=%s %s" % (rc3, out3))
        rc4, out4 = run(["git", "push", "-q"], allow_fail=True)
        lines.append("[git push] rc=%s %s" % (rc4, out4))
    else:
        lines.append("[git] 无改动，跳过 commit/push")

    lines.append("==== done %s ====" % datetime.now().strftime("%H:%M:%S"))
    text = "\n".join(lines)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
