<#
.SYNOPSIS
    Melody App Release & In-App Update Publisher
.DESCRIPTION
    Builds the production APK, stages and commits git changes, pushes to GitHub,
    and publishes the release so all installed Melody apps receive in-app updates.
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

Write-Host "`nTarget Release Version: v${Version}" -ForegroundColor Green
Write-Host "Changelog: $Changelog" -ForegroundColor Gray

# 2. Compile Optimized Release APK
Write-Host "`nCompiling optimized release APK..." -ForegroundColor Cyan
& "d:\flutter\bin\flutter.bat" build apk --release

$apkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkPath)) {
    Write-Error "Release APK was not found at $apkPath"
    exit 1
}

$apkItem = Get-Item $apkPath
$sizeMB = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host "`n[SUCCESS] Built release APK: $apkPath ($sizeMB MB)" -ForegroundColor Green

# 3. Generate version.json manifest
$manifestObj = @{
    version = $Version
    releaseName = "Melody v${Version}"
    downloadUrl = "https://github.com/justabean0/melody/releases/download/v${Version}/app-release.apk"
    changelog = $Changelog
    apkSize = $apkItem.Length
}
$manifestPath = "$ProjectDir\build\version.json"
$manifestObj | ConvertTo-Json -Depth 3 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "Generated update manifest at: $manifestPath" -ForegroundColor Cyan

# 4. Git Stage, Commit & Push
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

# 5. Publish to GitHub Release
$ghInstalled = Get-Command "gh" -ErrorAction SilentlyContinue
if ($ghInstalled) {
    Write-Host "`nGitHub CLI detected. Creating GitHub Release..." -ForegroundColor Cyan
    try {
        gh release create "v${Version}" "$apkPath" --title "Melody v${Version}" --notes "$Changelog"
        Write-Host "`n[SUCCESS] Release published to GitHub! All installed Melody apps will now prompt users to update in-app." -ForegroundColor Green
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

Write-Host "`nOpening File Explorer to your release APK..." -ForegroundColor Yellow
Start-Process explorer.exe -ArgumentList "/select,$apkPath"

Write-Host "`nNext steps to publish in 5 seconds:" -ForegroundColor Green
Write-Host "1. In the opened GitHub webpage, verify Tag is 'v${Version}'."
Write-Host "2. Drag and drop 'app-release.apk' from the opened folder into the 'Attach binaries' box."
Write-Host "3. Click 'Publish release'!"
Write-Host "`nOnce published, all Melody apps will detect and install the update automatically!" -ForegroundColor Green
