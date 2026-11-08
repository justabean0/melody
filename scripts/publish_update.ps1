<#
.SYNOPSIS
    Melody App Release & In-App Update Helper
.DESCRIPTION
    Builds the production APK and helps publish releases so users get instant in-app update prompts.
#>

param(
    [string]$Version,
    [string]$Changelog = "Bug fixes, playback optimizations, and performance improvements."
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Melody In-App Update Publisher Helper   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Read or bump version
if (-not $Version) {
    $pubspec = Get-Content "pubspec.yaml" -Raw
    if ($pubspec -match "version:\s*([0-9\.\+]+)") {
        $currentVer = $matches[1]
        Write-Host "Current version in pubspec.yaml: $currentVer" -ForegroundColor Yellow
        $Version = Read-Host "Enter new version tag (e.g. 1.0.1) or press ENTER to keep current"
        if (-not $Version) {
            $Version = $currentVer.Split('+')[0]
        }
    }
}

Write-Host "`nTarget Version: $Version" -ForegroundColor Green
Write-Host "Changelog: $Changelog" -ForegroundColor Gray

# 2. Compile Release APK
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

# 3. Generate version.json manifest for static hostings (Firebase / Cloudflare / Raw Gist)
$manifestObj = @{
    version = $Version
    releaseName = "Melody v$Version"
    downloadUrl = "https://github.com/YOUR_USERNAME/melody/releases/download/v$Version/app-release.apk"
    changelog = $Changelog
    apkSize = $apkItem.Length
}
$manifestPath = "$ProjectDir\build\version.json"
$manifestObj | ConvertTo-Json -Depth 3 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "Generated update manifest at: $manifestPath" -ForegroundColor Cyan

# 4. Check for GitHub CLI
$ghInstalled = Get-Command "gh" -ErrorAction SilentlyContinue
if ($ghInstalled) {
    Write-Host "`nGitHub CLI detected. Would you like to publish this release directly to GitHub now?" -ForegroundColor Yellow
    $ans = Read-Host "Publish to GitHub? (y/n)"
    if ($ans -eq "y" -or $ans -eq "Y") {
        Write-Host "Creating GitHub release v$Version..." -ForegroundColor Cyan
        gh release create "v$Version" "$apkPath" --title "Melody v$Version" --notes "$Changelog"
        Write-Host "[SUCCESS] Release published to GitHub! All installed Melody apps will now prompt users to update in-app." -ForegroundColor Green
        exit 0
    }
}

Write-Host "`nNext steps to push this update to your users:" -ForegroundColor Yellow
Write-Host "1. Create a release tag 'v$Version' on your GitHub repository."
Write-Host "2. Drag and drop '$apkPath' into the release assets."
Write-Host "3. Or upload '$manifestPath' and 'app-release.apk' to your web server / Firebase / Cloudflare."
Write-Host "`nAll users running Melody will automatically receive an in-app update popup with 1-click install!" -ForegroundColor Green
