<#
.SYNOPSIS
    Melody App Release & In-App Update Publisher
.DESCRIPTION
    Builds production and debug APKs, validates version codes, stages and commits git changes,
    pushes to GitHub, and publishes the release so all installed Melody apps receive in-app updates.
#>

param(
    [string]$Version,
    [string]$Changelog = "Bug fixes, playback optimizations, anti-bot protection, and performance improvements."
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Melody In-App Update Publisher Helper   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Read or bump version
$pubspecPath = "$ProjectDir\pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw
$currentVer = "1.0.0"
$buildNum = 1

if ($pubspec -match "version:\s*([0-9\.]+)\+?([0-9]*)") {
    $currentVer = $matches[1]
    if ($matches[2]) {
        $buildNum = [int]$matches[2]
    }
}

if (-not $Version) {
    Write-Host "Current version in pubspec.yaml: $currentVer (build $buildNum)" -ForegroundColor Yellow
    $suggestedVer = $currentVer
    $verParts = $currentVer.Split('.')
    if ($verParts.Length -eq 3) {
        $patch = [int]$verParts[2] + 1
        $suggestedVer = "$($verParts[0]).$($verParts[1]).$patch"
    }
    Write-Host "Press ENTER to use current version '$currentVer', or type a new version tag (e.g. $suggestedVer):" -ForegroundColor Cyan
    $entered = Read-Host "Version"
    if ($entered) {
        $Version = $entered.Trim().TrimStart('v')
        $buildNum++
        $newVersionString = "version: $Version+$buildNum"
        $pubspec = $pubspec -replace "version:\s*[0-9\.\+]+", $newVersionString
        Set-Content -Path $pubspecPath -Value $pubspec -Encoding UTF8
        Write-Host "Updated pubspec.yaml to $Version+$buildNum" -ForegroundColor Green
    } else {
        $Version = $currentVer
        Write-Host "Keeping current version $Version+$buildNum" -ForegroundColor Green
    }
} else {
    $Version = $Version.Trim().TrimStart('v')
}

Write-Host "`nTarget Release Version: v${Version} (build $buildNum)" -ForegroundColor Green
Write-Host "Changelog: $Changelog" -ForegroundColor Gray

# 2. Compile Release & Debug APKs
Write-Host "`n[1/2] Compiling optimized release APK..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build release APK!"
    exit 1
}

$releaseApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $releaseApkPath)) {
    Write-Error "Release APK was not found at $releaseApkPath"
    exit 1
}
$releaseApkItem = Get-Item $releaseApkPath
$releaseSizeMB = [math]::Round($releaseApkItem.Length / 1MB, 2)
Write-Host "[SUCCESS] Built release APK: $releaseApkPath ($releaseSizeMB MB)" -ForegroundColor Green

Write-Host "`n[2/2] Compiling debug APK..." -ForegroundColor Cyan
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build debug APK!"
    exit 1
}

$rawDebugApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-debug.apk"
$debugApkPath = "$ProjectDir\build\app\outputs\flutter-apk\melody-debug.apk"
if (-not (Test-Path $rawDebugApkPath)) {
    Write-Error "Debug APK was not found at $rawDebugApkPath"
    exit 1
}
Copy-Item -Path $rawDebugApkPath -Destination $debugApkPath -Force
$debugApkItem = Get-Item $debugApkPath
$debugSizeMB = [math]::Round($debugApkItem.Length / 1MB, 2)
Write-Host "[SUCCESS] Built debug APK: $debugApkPath ($debugSizeMB MB)" -ForegroundColor Green

# 3. AAPT Verification of both APKs
Write-Host "`nVerifying APK version metadata via aapt..." -ForegroundColor Cyan
$aaptPath = $null
if ($env:ANDROID_HOME -and (Test-Path "$env:ANDROID_HOME\build-tools")) {
    $aaptPath = (Get-ChildItem -Path "$env:ANDROID_HOME\build-tools" -Filter aapt.exe -Recurse | Select-Object -ExpandProperty FullName -First 1)
}
if (-not $aaptPath -and (Test-Path "$env:LOCALAPPDATA\Android\Sdk\build-tools")) {
    $aaptPath = (Get-ChildItem -Path "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Filter aapt.exe -Recurse | Select-Object -ExpandProperty FullName -First 1)
}
if (-not $aaptPath) {
    $cmd = Get-Command aapt -ErrorAction SilentlyContinue
    if ($cmd) { $aaptPath = $cmd.Source }
}

if (-not $aaptPath) {
    Write-Error "aapt.exe could not be found in Android SDK build-tools to verify APK version metadata."
    exit 1
}

function Verify-ApkMetadata {
    param(
        [string]$ApkFilePath,
        [string]$ExpectedVersionName,
        [string]$ExpectedVersionCode
    )
    $badging = & $aaptPath dump badging $ApkFilePath
    $pkgLine = ($badging | Select-String "package: " | Select-Object -First 1).Line
    $actualCode = ""
    $actualName = ""
    if ($pkgLine -match "versionCode='([^']+)'") { $actualCode = $matches[1] }
    if ($pkgLine -match "versionName='([^']+)'") { $actualName = $matches[1] }

    if ($actualCode -ne $ExpectedVersionCode -or $actualName -ne $ExpectedVersionName) {
        Write-Error "Version mismatch in $ApkFilePath! Expected: $ExpectedVersionName+$ExpectedVersionCode, Found: $actualName+$actualCode"
        exit 1
    }
    Write-Host "  Verified $ApkFilePath -> $actualName+$actualCode" -ForegroundColor Green
}

Verify-ApkMetadata -ApkFilePath $releaseApkPath -ExpectedVersionName "$Version" -ExpectedVersionCode "$buildNum"
Verify-ApkMetadata -ApkFilePath $debugApkPath -ExpectedVersionName "$Version-debug" -ExpectedVersionCode "$buildNum"

# 4. Generate version.json manifest
$manifestObj = @{
    version = $Version
    releaseName = "Melody v${Version}"
    downloadUrl = "https://github.com/justabean0/melody/releases/download/v${Version}/app-release.apk"
    debugDownloadUrl = "https://github.com/justabean0/melody/releases/download/v${Version}/melody-debug.apk"
    changelog = $Changelog
    apkSize = $releaseApkItem.Length
    debugApkSize = $debugApkItem.Length
}
$manifestPath = "$ProjectDir\build\version.json"
$manifestObj | ConvertTo-Json -Depth 3 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "`nGenerated update manifest at: $manifestPath" -ForegroundColor Cyan

# 5. Git Stage, Commit & Push
Write-Host "`nUpdating Git repository..." -ForegroundColor Cyan
$gitStatus = git status --porcelain
if ($gitStatus) {
    git add .
    git commit -m "Release v${Version} - $Changelog"
    Write-Host "Committed changes to git." -ForegroundColor Green
} else {
    Write-Host "Working directory is already clean." -ForegroundColor Gray
}

Write-Host "Pushing code to origin main..." -ForegroundColor Cyan
try {
    git push origin main
    Write-Host "Pushed commits to origin main." -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not push to main automatically. Please push when ready." -ForegroundColor Yellow
}

# Create and push git tag
Write-Host "Tagging release v${Version}..." -ForegroundColor Cyan
try {
    git tag -a "v${Version}" -m "Melody v${Version}"
    git push origin "v${Version}"
    Write-Host "Pushed tag v${Version} to GitHub." -ForegroundColor Green
} catch {
    Write-Host "Note: Tag v${Version} already exists or could not be pushed." -ForegroundColor Yellow
}

# 6. Publish to GitHub Release
$ghInstalled = Get-Command "gh" -ErrorAction SilentlyContinue
if ($ghInstalled) {
    Write-Host "`nGitHub CLI detected. Creating GitHub Release..." -ForegroundColor Cyan
    try {
        gh release create "v${Version}" "$releaseApkPath" "$debugApkPath" --title "Melody v${Version}" --notes "$Changelog"
        Write-Host "`n[SUCCESS] Release published to GitHub! Both release and debug APKs uploaded." -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "GitHub CLI release creation failed. Falling back to browser..." -ForegroundColor Yellow
    }
}

# Browser release fallback
$newReleaseUrl = "https://github.com/justabean0/melody/releases/new?tag=v${Version}&title=Melody+v${Version}"
Write-Host "`nOpening GitHub release page in your browser..." -ForegroundColor Yellow
Write-Host "URL: $newReleaseUrl" -ForegroundColor Cyan
Start-Process $newReleaseUrl

Write-Host "`nOpening File Explorer to your release APKs..." -ForegroundColor Yellow
Start-Process explorer.exe -ArgumentList "/select,$releaseApkPath"

Write-Host "`nNext steps to publish:" -ForegroundColor Green
Write-Host "1. In the opened GitHub webpage, verify Tag is 'v${Version}'."
Write-Host "2. Drag and drop 'app-release.apk' and 'melody-debug.apk' into the 'Attach binaries' box."
Write-Host "3. Click 'Publish release'!"
Write-Host "`nOnce published, all Melody apps will detect and install updates automatically!" -ForegroundColor Green
