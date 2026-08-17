@echo off
setlocal

rem === Environment (mirror CI build) ===
set JAVA_HOME=D:\Android\jdk-17.0.2
set ANDROID_HOME=D:\Android\sdk
set GRADLE_USER_HOME=D:\Android\.gradle
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

rem === Go to mobile project (next to this bat) ===
cd /d "%~dp0mobile"

echo === flutter clean ===
call "D:\Android\flutter\bin\flutter.bat" clean

echo === flutter pub get ===
call "D:\Android\flutter\bin\flutter.bat" pub get

echo === flutter build apk --release (android-arm64) ===
call "D:\Android\flutter\bin\flutter.bat" build apk --release --target-platform android-arm64

set BUILD_RC=%errorlevel%
echo BUILD_RC=%BUILD_RC%

if "%BUILD_RC%"=="0" (
  echo.
  echo BUILD OK - APK at mobile\build\app\outputs\flutter-apk\app-release.apk
) else (
  echo.
  echo BUILD FAILED - check log above.
)
if not defined AUTOMATED pause
exit /b %BUILD_RC%
