# -*- coding: utf-8 -*-
"""把本地课程表文件 schedule.local.json 推送到 GitHub 仓库的 schedule.json。

用法：
  python push_schedule.py            # 读取 schedule.local.json 推送
  python push_schedule.py my.json    # 指定文件推送

需要环境变量 GITHUB_TOKEN（仅 repo 权限），或交互输入。
用于：本机维护课程表，不想走网页 Token 时，由命令行 / 定时任务推送。
"""
import os
import sys
import json
import base64
import urllib.request
import urllib.error

REPO = "W-lik721/personal-workbench"
API = "https://api.github.com/repos/%s/contents/schedule.json" % REPO
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "schedule.local.json")
    if not os.path.isfile(src):
        print("源文件不存在：%s" % src)
        return 1
    with open(src, "r", encoding="utf-8") as f:
        list_data = json.load(f)
    content = base64.b64encode(json.dumps(list_data, ensure_ascii=False, indent=2).encode("utf-8")).decode("ascii")

    token = os.environ.get("GITHUB_TOKEN") or input("GitHub Token: ").strip()
    if not token:
        print("未提供 Token")
        return 1

    req = urllib.request.Request(API, headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json"})
    sha = None
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            meta = json.loads(r.read().decode("utf-8"))
            sha = meta.get("sha")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print("读取现有文件失败：", e.read().decode("utf-8", "replace"))
            return 1

    body = json.dumps({"message": "chore: update schedule from local", "content": content, "sha": sha}).encode("utf-8")
    preq = urllib.request.Request(API, data=body, method="PUT",
                                   headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                                             "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(preq, timeout=15) as r:
            print("✅ 已推送 %d 条课程到 GitHub schedule.json" % len(list_data))
            return 0
    except urllib.error.HTTPError as e:
        print("推送失败：", e.read().decode("utf-8", "replace"))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
