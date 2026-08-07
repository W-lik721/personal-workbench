# -*- coding: utf-8 -*-
"""工作台每小时同步脚本（替代 sync_core.cmd，供 Windows 任务计划程序调用）。"""
import os
import subprocess
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
ENV = dict(os.environ)
ENV["PYTHONIOENCODING"] = "utf-8"
ENV["GIT_SSL_NO_VERIFY"] = "true"


def run(cmd, allow_fail=False, timeout=180):
    p = subprocess.run(cmd, cwd=HERE, env=ENV, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=timeout)
    out = (p.stdout or "") + (p.stderr or "")
    if not allow_fail and p.returncode != 0:
        raise RuntimeError(f"{cmd} failed rc={p.returncode}: {out}")
    return p.returncode, out.strip()


def main():
    from sync_status import write_sync_status
    lines = [f"==== sync {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===="]
    data_path = os.path.join(HERE, "data.json")

    rc, out = run([PY, "export_data.py"], allow_fail=True)
    lines.append(f"[export_data.py] rc={rc}\n{out}")
    export_ok = (rc == 0)

    run(["git", "pull", "--rebase", "--autostash", "-q"], allow_fail=True)
    run(["git", "add", "data.json"], allow_fail=True)

    push_ok = True
    rc, _ = run(["git", "diff", "--cached", "--quiet"], allow_fail=True)
    if rc != 0:
        ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
        rc2, out2 = run(["git", "commit", "-q", "-m", f"chore: auto-sync data {ts}"], allow_fail=True)
        lines.append(f"[git commit] rc={rc2} {out2}")
        rc3, out3 = run(["git", "push", "-q"], allow_fail=True)
        lines.append(f"[git push] rc={rc3} {out3}")
        push_ok = (rc3 == 0)
    else:
        lines.append("[git] 无改动，跳过 commit/push")

    # 把同步健康度写进 data.json，再推一次（让面板能显示失败/陈旧告警）
    sync = write_sync_status(data_path, ok=(export_ok and push_ok))
    lines.append(f"[sync status] {sync}")
    run(["git", "add", "data.json"], allow_fail=True)
    rc4, _ = run(["git", "diff", "--cached", "--quiet"], allow_fail=True)
    if rc4 != 0:
        run(["git", "commit", "-q", "-m", "chore: update sync health status"], allow_fail=True)
        run(["git", "push", "-q"], allow_fail=True)

    lines.append(f"==== done {datetime.now().strftime('%H:%M:%S')} ====")
    write_log(lines)
    return 0


def write_log(lines):
    text = "\n".join(lines)
    with open(os.path.join(HERE, "sync.log"), "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(text)


if __name__ == "__main__":
    raise SystemExit(main())
