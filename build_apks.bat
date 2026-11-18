@echo off
echo ========================================================
echo Building Melody Official Release and Debug APKs
echo ========================================================

echo.
echo [1/4] Building Release APK (com.melody.music)...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [ERROR] Failed to build release APK!
    exit /b %errorlevel%
)
copy /y build\app\outputs\flutter-apk\app-release.apk Melody-Release.apk >nul
echo [OK] Melody-Release.apk generated.

echo.
echo [2/4] Building Debug APK (com.melody.music.debug)...
call flutter build apk --debug
if %errorlevel% neq 0 (
    echo [ERROR] Failed to build debug APK!
    exit /b %errorlevel%
)
copy /y build\app\outputs\flutter-apk\app-debug.apk Melody-Debug.apk >nul
echo [OK] Melody-Debug.apk generated.

echo.
echo ========================================================
echo BUILD COMPLETE! Both APKs are ready for GitHub Releases:
echo.
echo  - Melody-Release.apk  - Package: com.melody.music       - Label: Melody
echo  - Melody-Debug.apk    - Package: com.melody.music.debug - Label: Melody (Debug)
echo.
echo You can upload both files to your GitHub Release!
echo Release users will ONLY receive release updates.
echo ========================================================
