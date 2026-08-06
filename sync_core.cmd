@echo off
cd /d D:\Users\qingdeng-ws\personal-workbench
"C:\Users\13115\.workbuddy\binaries\python\versions\3.13.12\python.exe" export_data.py
git pull --rebase -q
git add data.json
git diff --cached --quiet || git commit -q -m "chore: auto-sync data %date% %time%"
set GIT_SSL_NO_VERIFY=true
git push -q
