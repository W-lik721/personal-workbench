@echo off
echo 正在删除旧的 Workbench 定时任务...
schtasks /Delete /TN "WorkbenchAutoSync" /F 2>nul
schtasks /Delete /TN "WorkbenchAiDaily" /F 2>nul
echo.
echo 完成。如果提示"找不到任务"说明已经删过了，不用管。
pause
