@echo off
echo ==========================================
echo  WorkBench Crash Log Catcher
echo  Step 1: Enable USB debugging on your phone
echo  Step 2: Connect phone to PC via USB
echo  Step 3: Press any key, then OPEN the app to crash
echo  Step 4: Return here and press any key again
echo ==========================================
pause
set ADB=D:\Android\sdk\platform-tools\adb.exe
echo Clearing old logcat buffer...
"%ADB%" logcat -c
echo Now OPEN the app and make it crash, then come back.
pause
echo Saving crash logs to mobile\crash_log.txt ...
"%ADB%" logcat -d > mobile\crash_log.txt
echo ==========================================
echo  DONE. Open mobile\crash_log.txt and send it.
echo ==========================================
pause
