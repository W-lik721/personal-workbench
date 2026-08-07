# -*- coding: utf-8 -*-
"""工作台同步：本机 self-hosted runner 上生成 data.json，通过 GitHub API 推回仓库。

设计要点：
- 不依赖本地 git 仓库状态（避免复用工作区 checkout 后 git 命令报
  "not in a git directory"）。推送走 GitHub Contents API + GITHUB_TOKEN。
- deploy-pages.yml 在 push 到 main（或本工作流 completed）时自动重新部署 Pages，
  所以线上面板会拿到最新 data.json。
- 诊断日志写到仓库外的 D:\Users\qingdeng-ws\sync_diag.log，避免被 checkout 的
  git clean 清掉，方便失败时本地排查。
"""
import os
import sys
import json
import base64
import subprocess
import urllib.request
import urllib.error
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
ENV = dict(os.environ)
ENV["PYTHONIOENCODING"] = "utf-8"

REPO = "W-lik721/personal-workbench"
API = "https://api.github.com"
DIAG = r"D:\Users\qingdeng-ws\sync_diag.log"


def diag(msg):
    try:
        with open(DIAG, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (datetime.now().strftime("%H:%M:%S"), msg))
    except Exception:
        pass


def run_py(script, timeout=300):
    p = subprocess.run([PY, script], cwd=HERE, env=ENV, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=timeout)
    out = (p.stdout or "") + (p.stderr or "")
    return p.returncode, out.strip()


def api_request(method, url, data=None, token=None, retries=3):
    headers = {
        "Authorization": "Bearer %s" % token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "workbuddy-sync",
    }
    payload = json.dumps(data).encode("utf-8") if data is not None else None
    if payload is not None:
        headers["Content-Type"] = "application/json"
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=payload, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read().decode("utf-8", "replace")
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as e:
            last = e
            detail = ""
            try:
                detail = e.read().decode("utf-8", "replace")
            except Exception:
                pass
            diag("API %s -> HTTP %d: %s" % (method, e.code, detail[:400]))
            if e.code == 409 and method == "PUT":
                raise  # 交给调用方用最新 sha 重试
            if e.code >= 500 and attempt < retries - 1:
                continue
            raise RuntimeError("GitHub API %s 失败 %d: %s" % (method, e.code, detail[:400]))
        except Exception as e:
            last = e
            diag("API %s 异常: %s" % (method, e))
            if attempt < retries - 1:
                continue
            raise
    if last:
        raise last


def push_data(token):
    """把本地 data.json 推送到仓库（Contents API）。成功返回 True。"""
    url = "%s/repos/%s/contents/data.json" % (API, REPO)
    try:
        cur = api_request("GET", url, token=token)
        sha = cur.get("sha") if isinstance(cur, dict) else None
    except Exception as e:
        diag("GET 当前 sha 失败: %s" % e)
        sha = None
    with open(os.path.join(HERE, "data.json"), "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")
    body = {
        "message": "chore: auto-sync data %s" % datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "content": content,
    }
    if sha:
        body["sha"] = sha
    try:
        api_request("PUT", url, data=body, token=token)
        diag("PUT data.json 成功 (sha=%s)" % (sha or "new"))
        return True
    except RuntimeError as e:
        if "409" in str(e):  # 并发更新，取最新 sha 重试一次
            try:
                cur = api_request("GET", url, token=token)
                sha = cur.get("sha") if isinstance(cur, dict) else None
                if sha:
                    body["sha"] = sha
                    api_request("PUT", url, data=body, token=token)
                    diag("PUT data.json 重试成功")
                    return True
            except Exception as e2:
                diag("PUT 重试失败: %s" % e2)
        diag("PUT data.json 最终失败")
        return False


def main():
    diag("==== sync 开始 cwd=%s HERE=%s ====" % (os.getcwd(), HERE))
    token = os.environ.get("GITHUB_TOKEN")
    diag("GITHUB_TOKEN 存在=%s" % bool(token))
    if not token:
        diag("ERROR: 缺少 GITHUB_TOKEN，无法推送 data.json")
        return 1

    from sync_status import write_sync_status
    lines = ["==== sync %s ====" % datetime.now().strftime("%Y-%m-%d %H:%M:%S")]
    data_path = os.path.join(HERE, "data.json")

    rc, out = run_py("export_data.py")
    lines.append("[export_data.py] rc=%d\n%s" % (rc, out))
    diag("[export_data.py] rc=%d" % rc)
    export_ok = (rc == 0)

    push1_ok = push_data(token)
    diag("push1_ok=%s" % push1_ok)

    # 把同步健康度（成功/失败/陈旧告警）写回 data.json
    try:
        st = write_sync_status(data_path, ok=(export_ok and push1_ok))
        lines.append("[sync status] %s" % st)
    except Exception as e:
        lines.append("[sync status 错误] %s" % e)

    # 再推一次，让线上的 sync.status 也最新（刷新按钮据此判断成功/失败）
    push2_ok = push_data(token)
    diag("push2_ok=%s" % push2_ok)

    ok = export_ok and push1_ok and push2_ok
    lines.append("==== done %s %s ====" % ("OK" if ok else "FAIL", datetime.now().strftime("%H:%M:%S")))
    write_log(lines)
    diag("==== sync 结束 ok=%s ====" % ok)
    return 0 if ok else 1


def write_log(lines):
    text = "\n".join(lines)
    with open(os.path.join(HERE, "sync.log"), "w", encoding="utf-8") as f:
        f.write(text + "\n")
    try:
        print(text)
    except UnicodeEncodeError:
        fb = text.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(
            sys.stdout.encoding or "utf-8")
        print(fb)


if __name__ == "__main__":
    try:
        code = main()
    except Exception as e:
        diag("FATAL: %s" % e)
        import traceback
        diag(traceback.format_exc())
        code = 1
    raise SystemExit(code)
