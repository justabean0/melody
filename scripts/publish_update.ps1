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
    if ($Version -ne $currentVer) {
        $buildNum++
        $newVersionString = "version: $Version+$buildNum"
        $pubspec = $pubspec -replace "version:\s*[0-9\.\+]+", $newVersionString
        Set-Content -Path $pubspecPath -Value $pubspec -Encoding UTF8
        Write-Host "Updated pubspec.yaml to $Version+$buildNum" -ForegroundColor Green
    }
}

# Sync lib/services/update_service.dart constants to match pubspec.yaml
$updateServicePath = "$ProjectDir\lib\services\update_service.dart"
if (Test-Path $updateServicePath) {
    $updateServiceContent = Get-Content $updateServicePath -Raw
    $updateServiceContent = $updateServiceContent -replace "static const String appVersion = '[^']+';", "static const String appVersion = '$Version';"
    $updateServiceContent = $updateServiceContent -replace "static const int appBuildNumber = \d+;", "static const int appBuildNumber = $buildNum;"
    Set-Content -Path $updateServicePath -Value $updateServiceContent -Encoding UTF8
    Write-Host "Synced update_service.dart constants to $Version+$buildNum" -ForegroundColor Green
}

Write-Host "`nTarget Release Version: v${Version} (build $buildNum)" -ForegroundColor Green
Write-Host "Changelog: $Changelog" -ForegroundColor Gray

# Run verification before building
Write-Host "`nRunning code analysis..." -ForegroundColor Cyan
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Error "Static analysis failed with errors!"
    exit 1
}

Write-Host "`nRunning test suite..." -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Error "Unit tests failed!"
    exit 1
}
Write-Host "All tests and static analysis passed." -ForegroundColor Green

# 2. Compile Standard Release & Diag Release APKs
Write-Host "`n[1/2] Compiling standard release APK (flavor: standard)..." -ForegroundColor Cyan
flutter build apk --release --flavor standard
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build standard release APK!"
    exit 1
}

$rawStandardApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-standard-release.apk"
$releaseApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $rawStandardApkPath)) {
    Write-Error "Standard release APK was not found at $rawStandardApkPath"
    exit 1
}
Copy-Item -Path $rawStandardApkPath -Destination $releaseApkPath -Force
$releaseApkItem = Get-Item $releaseApkPath
$releaseSizeMB = [math]::Round($releaseApkItem.Length / 1MB, 2)
Write-Host "[SUCCESS] Built release APK: $releaseApkPath ($releaseSizeMB MB)" -ForegroundColor Green

Write-Host "`n[2/2] Compiling diag release APK (flavor: diag, ENABLE_DIAGNOSTICS=true)..." -ForegroundColor Cyan
flutter build apk --release --flavor diag --dart-define=ENABLE_DIAGNOSTICS=true
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build diag release APK!"
    exit 1
}

$rawDiagApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-diag-release.apk"
$debugApkPath = "$ProjectDir\build\app\outputs\flutter-apk\melody-debug.apk"
if (-not (Test-Path $rawDiagApkPath)) {
    Write-Error "Diag release APK was not found at $rawDiagApkPath"
    exit 1
}
Copy-Item -Path $rawDiagApkPath -Destination $debugApkPath -Force
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
        [string]$ExpectedPackageName,
        [string]$ExpectedVersionName,
        [string]$ExpectedVersionCode
    )
    $badging = & $aaptPath dump badging $ApkFilePath
    $pkgLine = ($badging | Select-String "package: " | Select-Object -First 1).Line
    $actualPackage = ""
    $actualCode = ""
    $actualName = ""
    if ($pkgLine -match "name='([^']+)'") { $actualPackage = $matches[1] }
    if ($pkgLine -match "versionCode='([^']+)'") { $actualCode = $matches[1] }
    if ($pkgLine -match "versionName='([^']+)'") { $actualName = $matches[1] }

    if ($actualPackage -ne $ExpectedPackageName -or $actualCode -ne $ExpectedVersionCode -or $actualName -ne $ExpectedVersionName) {
        Write-Error "Metadata mismatch in $ApkFilePath! Expected: $ExpectedPackageName $ExpectedVersionName+$ExpectedVersionCode, Found: $actualPackage $actualName+$actualCode"
        exit 1
    }
    Write-Host "  Verified $ApkFilePath -> $actualPackage $actualName+$actualCode" -ForegroundColor Green
}

Verify-ApkMetadata -ApkFilePath $releaseApkPath -ExpectedPackageName "com.melody.music" -ExpectedVersionName "$Version" -ExpectedVersionCode "$buildNum"
Verify-ApkMetadata -ApkFilePath $debugApkPath -ExpectedPackageName "com.melody.music.debug" -ExpectedVersionName "$Version-debug" -ExpectedVersionCode "$buildNum"

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
    git add android/ lib/ scripts/ test/ pubspec.yaml
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
if (Test-Path "C:\Program Files\GitHub CLI") {
    $env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"
}
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
