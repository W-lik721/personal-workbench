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
    lines = [f"==== sync {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===="]

    rc, out = run([PY, "export_data.py"], allow_fail=True)
    lines.append(f"[export_data.py] rc={rc}\n{out}")
    if rc != 0:
        lines.append("[ERROR] export failed, abort")
        write_log(lines)
        return rc

    run(["git", "pull", "--rebase", "--autostash", "-q"], allow_fail=True)
    run(["git", "add", "data.json"], allow_fail=True)

    rc, _ = run(["git", "diff", "--cached", "--quiet"], allow_fail=True)
    if rc != 0:
        ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
        rc2, out2 = run(["git", "commit", "-q", "-m", f"chore: auto-sync data {ts}"], allow_fail=True)
        lines.append(f"[git commit] rc={rc2} {out2}")
        rc3, out3 = run(["git", "push", "-q"], allow_fail=True)
        lines.append(f"[git push] rc={rc3} {out3}")
    else:
        lines.append("[git] 无改动，跳过 commit/push")

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
