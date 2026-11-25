<#
.SYNOPSIS
    Melody App Release & In-App Update Publisher
.DESCRIPTION
    Builds (or reuses with -SkipBuild) production and debug APKs, verifies package
    metadata and Play Protect permissions via aapt, updates release files safely
    without UTF-8 BOM, pushes git changes and tags, and publishes to GitHub Releases.
#>

param(
    [string]$Version,
    [string]$Changelog = "Bug fixes, playback optimizations, anti-bot protection, and performance improvements.",
    [switch]$AutoUpload,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

if (Test-Path "C:\Program Files\GitHub CLI") {
    $pathParts = $env:PATH -split ';'
    if (-not ($pathParts -contains "C:\Program Files\GitHub CLI")) {
        $env:PATH = "C:\Program Files\GitHub CLI;$env:PATH"
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Melody In-App Update Publisher Helper   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Read or bump version (write only when values actually change, UTF-8 without BOM)
$pubspecPath = "$ProjectDir\pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    Write-Error "pubspec.yaml not found at $pubspecPath"
    exit 1
}

$pubspec = [System.IO.File]::ReadAllText($pubspecPath)
$currentVer = "1.0.0"
$buildNum = 1
$parsedVer = $null
$parsedBuild = $null

if ($pubspec -match "(?m)^version:\s*([0-9\.]+)\+?([0-9]*)") {
    $currentVer = $matches[1]
    $parsedVer = $currentVer
    if ($matches[2]) {
        $buildNum = [int]$matches[2]
        $parsedBuild = $buildNum
    } else {
        $parsedBuild = 1
    }
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
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
        if ($Version -ne $currentVer) {
            $buildNum++
        }
    } else {
        $Version = $currentVer
    }
} else {
    $Version = $Version.Trim().TrimStart('v')
    if ($Version -ne $currentVer) {
        $buildNum++
    }
}

if ($Version -ne $parsedVer -or $buildNum -ne $parsedBuild) {
    $newVersionString = "version: $Version+$buildNum"
    $updatedPubspec = $pubspec -replace "(?m)^version:\s*[0-9\.\+]+", $newVersionString
    if ($updatedPubspec -ne $pubspec) {
        [System.IO.File]::WriteAllText($pubspecPath, $updatedPubspec, $Utf8NoBom)
        Write-Host "Updated pubspec.yaml to $Version+$buildNum" -ForegroundColor Green
    }
} else {
    Write-Host "pubspec.yaml already at $Version+$buildNum (skipping write)." -ForegroundColor Gray
}

# Sync lib/services/update_service.dart constants only when values actually differ
$updateServicePath = "$ProjectDir\lib\services\update_service.dart"
if (Test-Path $updateServicePath) {
    $updateServiceContent = [System.IO.File]::ReadAllText($updateServicePath)
    $existingAppVersion = $null
    $existingAppBuild = $null
    if ($updateServiceContent -match "static const String appVersion = '([^']+)';") {
        $existingAppVersion = $matches[1]
    }
    if ($updateServiceContent -match "static const int appBuildNumber = (\d+);") {
        $existingAppBuild = [int]$matches[1]
    }

    if ($existingAppVersion -ne $Version -or $existingAppBuild -ne $buildNum) {
        $updatedServiceContent = $updateServiceContent -replace "static const String appVersion = '[^']+';", "static const String appVersion = '$Version';"
        $updatedServiceContent = $updatedServiceContent -replace "static const int appBuildNumber = \d+;", "static const int appBuildNumber = $buildNum;"
        if ($updatedServiceContent -ne $updateServiceContent) {
            [System.IO.File]::WriteAllText($updateServicePath, $updatedServiceContent, $Utf8NoBom)
            Write-Host "Synced update_service.dart constants to $Version+$buildNum" -ForegroundColor Green
        }
    } else {
        Write-Host "update_service.dart already synced at $Version+$buildNum (skipping write)." -ForegroundColor Gray
    }
}

Write-Host "`nTarget Release Version: v${Version} (build $buildNum)" -ForegroundColor Green
Write-Host "Changelog: $Changelog" -ForegroundColor Gray

# Guard early against existing local tag, remote tag, or GitHub Release
Write-Host "`nChecking whether tag/release v${Version} already exists..." -ForegroundColor Cyan
$localTag = & git tag -l "v${Version}"
if ($LASTEXITCODE -ne 0) {
    Write-Error "git tag check failed (exit $LASTEXITCODE)!"
    exit 1
}
if (($localTag | Out-String).Trim()) {
    Write-Error "Git tag v${Version} already exists locally! Aborting."
    exit 1
}

$remoteTag = & git ls-remote --tags origin "refs/tags/v${Version}"
if ($LASTEXITCODE -ne 0) {
    Write-Error "git ls-remote check failed (exit $LASTEXITCODE)!"
    exit 1
}
if (($remoteTag | Out-String).Trim()) {
    Write-Error "Git tag v${Version} already exists on origin! Aborting."
    exit 1
}

$ghCmd = Get-Command "gh" -ErrorAction SilentlyContinue
if ($AutoUpload -and -not $ghCmd) {
    Write-Error "GitHub CLI (gh) could not be found in PATH, but -AutoUpload was requested."
    exit 1
}
if ($ghCmd) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $ghReleaseCheck = & gh release view "v${Version}" --json tagName 2>&1
    $ghCheckExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($ghCheckExit -eq 0) {
        Write-Error "GitHub release v${Version} already exists! Aborting."
        exit 1
    }
    $ghCheckMsg = ($ghReleaseCheck | Out-String).Trim()
    if ($ghCheckMsg -and $ghCheckMsg -notmatch "release not found|HTTP 404") {
        if ($AutoUpload) {
            Write-Error "Failed to verify GitHub release status via gh (exit $ghCheckExit): $ghCheckMsg"
            exit 1
        } else {
            Write-Host "Warning: Unable to verify GitHub release state via gh: $ghCheckMsg" -ForegroundColor Yellow
        }
    }
}

# Run verification before building/packaging
Write-Host "`nRunning code analysis..." -ForegroundColor Cyan
& flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Error "Static analysis failed (exit $LASTEXITCODE)!"
    exit 1
}

Write-Host "`nRunning test suite..." -ForegroundColor Cyan
& flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Error "Unit tests failed (exit $LASTEXITCODE)!"
    exit 1
}
Write-Host "All tests and static analysis passed." -ForegroundColor Green

# 2. Compile or reuse Standard Release & Diag Release APKs
$rawStandardApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-standard-release.apk"
$releaseApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
$rawDiagApkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-diag-release.apk"
$debugApkPath = "$ProjectDir\build\app\outputs\flutter-apk\melody-debug.apk"

if ($SkipBuild) {
    Write-Host "`n-SkipBuild enabled: reusing existing standard and diag release APKs..." -ForegroundColor Yellow
} else {
    Write-Host "`n[1/2] Compiling standard release APK (flavor: standard)..." -ForegroundColor Cyan
    & flutter build apk --release --flavor standard
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build standard release APK (exit $LASTEXITCODE)!"
        exit 1
    }

    Write-Host "`n[2/2] Compiling diag release APK (flavor: diag, ENABLE_DIAGNOSTICS=true)..." -ForegroundColor Cyan
    & flutter build apk --release --flavor diag --dart-define=ENABLE_DIAGNOSTICS=true
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build diag release APK (exit $LASTEXITCODE)!"
        exit 1
    }
}

if (-not (Test-Path $rawStandardApkPath)) {
    Write-Error "Standard release APK was not found at $rawStandardApkPath"
    exit 1
}
if (-not (Test-Path $rawDiagApkPath)) {
    Write-Error "Diag release APK was not found at $rawDiagApkPath"
    exit 1
}

Copy-Item -Path $rawStandardApkPath -Destination $releaseApkPath -Force
$releaseApkItem = Get-Item $releaseApkPath
$releaseSizeMB = [math]::Round($releaseApkItem.Length / 1MB, 2)
Write-Host "[SUCCESS] Prepared release APK: $releaseApkPath ($releaseSizeMB MB)" -ForegroundColor Green

Copy-Item -Path $rawDiagApkPath -Destination $debugApkPath -Force
$debugApkItem = Get-Item $debugApkPath
$debugSizeMB = [math]::Round($debugApkItem.Length / 1MB, 2)
Write-Host "[SUCCESS] Prepared debug APK: $debugApkPath ($debugSizeMB MB)" -ForegroundColor Green

# 3. AAPT Verification of both APKs (metadata + Play Protect permission gate)
Write-Host "`nVerifying APK version metadata and permissions via aapt..." -ForegroundColor Cyan
$aaptPath = $null
if ($env:ANDROID_HOME -and (Test-Path "$env:ANDROID_HOME\build-tools")) {
    $aaptPath = (Get-ChildItem -Path "$env:ANDROID_HOME\build-tools" -Filter aapt.exe -Recurse | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName -First 1)
}
if (-not $aaptPath -and (Test-Path "$env:LOCALAPPDATA\Android\Sdk\build-tools")) {
    $aaptPath = (Get-ChildItem -Path "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Filter aapt.exe -Recurse | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName -First 1)
}
if (-not $aaptPath) {
    $cmd = Get-Command aapt -ErrorAction SilentlyContinue
    if ($cmd) { $aaptPath = $cmd.Source }
}

if (-not $aaptPath) {
    Write-Error "aapt.exe could not be found in Android SDK build-tools to verify APK metadata and permissions."
    exit 1
}

function Verify-ApkMetadata {
    param(
        [string]$ApkFilePath,
        [string]$ExpectedPackageName,
        [string]$ExpectedVersionName,
        [string]$ExpectedVersionCode
    )
    if (-not (Test-Path $ApkFilePath)) {
        Write-Error "APK file missing for aapt check: $ApkFilePath"
        exit 1
    }

    $badging = & $aaptPath dump badging $ApkFilePath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "aapt dump badging failed (exit $LASTEXITCODE) for $ApkFilePath"
        exit 1
    }

    $permissions = & $aaptPath dump permissions $ApkFilePath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "aapt dump permissions failed (exit $LASTEXITCODE) for $ApkFilePath"
        exit 1
    }

    $pkgLine = ($badging | Select-String "package:\s" | Select-Object -First 1).Line
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

    $hasRestrictedPerm = ($badging | Select-String "REQUEST_INSTALL_PACKAGES") -or ($permissions | Select-String "REQUEST_INSTALL_PACKAGES")
    if ($hasRestrictedPerm) {
        Write-Error "Play Protect check failed: REQUEST_INSTALL_PACKAGES permission is present in $ApkFilePath!"
        exit 1
    }

    Write-Host "  Verified $ApkFilePath -> $actualPackage $actualName+$actualCode (REQUEST_INSTALL_PACKAGES absent)" -ForegroundColor Green
}

Verify-ApkMetadata -ApkFilePath $releaseApkPath -ExpectedPackageName "com.melody.music" -ExpectedVersionName "$Version" -ExpectedVersionCode "$buildNum"
Verify-ApkMetadata -ApkFilePath $debugApkPath -ExpectedPackageName "com.melody.music.debug" -ExpectedVersionName "$Version-debug" -ExpectedVersionCode "$buildNum"

# 4. Generate version.json manifest (UTF-8 without BOM)
$manifestObj = [ordered]@{
    version = $Version
    buildNumber = $buildNum
    releaseName = "Melody v${Version}"
    downloadUrl = "https://github.com/justabean0/melody/releases/download/v${Version}/app-release.apk"
    debugDownloadUrl = "https://github.com/justabean0/melody/releases/download/v${Version}/melody-debug.apk"
    changelog = $Changelog
    apkSize = $releaseApkItem.Length
    debugApkSize = $debugApkItem.Length
}
$manifestPath = "$ProjectDir\build\version.json"
$manifestDir = Split-Path -Parent $manifestPath
if (-not (Test-Path $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}
$manifestJson = ($manifestObj | ConvertTo-Json -Depth 3) + [Environment]::NewLine
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $Utf8NoBom)
Write-Host "`nGenerated update manifest at: $manifestPath" -ForegroundColor Cyan

# 5. Git Stage (explicit tracked release files only), Commit, Push & Tag
Write-Host "`nUpdating Git repository..." -ForegroundColor Cyan
$trackedReleaseFiles = @("pubspec.yaml", "lib/services/update_service.dart")
$modifiedReleaseFiles = @()
foreach ($relFile in $trackedReleaseFiles) {
    if (Test-Path "$ProjectDir\$relFile") {
        $fileStatus = & git status --porcelain -- $relFile
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git status failed while checking $relFile (exit $LASTEXITCODE)!"
            exit 1
        }
        if (($fileStatus | Out-String).Trim()) {
            $modifiedReleaseFiles += $relFile
        }
    }
}

if ($modifiedReleaseFiles.Count -gt 0) {
    foreach ($relFile in $modifiedReleaseFiles) {
        & git add -- $relFile
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git add failed for $relFile (exit $LASTEXITCODE)!"
            exit 1
        }
    }
    & git commit -m "Release v${Version} - $Changelog"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git commit failed (exit $LASTEXITCODE)!"
        exit 1
    }
    Write-Host "Committed changes for: $($modifiedReleaseFiles -join ', ')" -ForegroundColor Green
} else {
    Write-Host "Release metadata files are already clean (skipping commit)." -ForegroundColor Gray
}

Write-Host "Pushing code to origin main..." -ForegroundColor Cyan
& git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Error "git push origin main failed (exit $LASTEXITCODE)!"
    exit 1
}
Write-Host "Pushed commits to origin main." -ForegroundColor Green

# Create and push git tag
Write-Host "Tagging release v${Version}..." -ForegroundColor Cyan
& git tag -a "v${Version}" -m "Melody v${Version}"
if ($LASTEXITCODE -ne 0) {
    Write-Error "git tag v${Version} failed (exit $LASTEXITCODE)!"
    exit 1
}
& git push origin "v${Version}"
if ($LASTEXITCODE -ne 0) {
    Write-Error "git push origin v${Version} failed (exit $LASTEXITCODE)!"
    exit 1
}
Write-Host "Pushed tag v${Version} to GitHub." -ForegroundColor Green

# 6. Publish to GitHub Release (strict sequential asset upload order)
if ($AutoUpload) {
    Write-Host "`nGitHub CLI detected. Publishing release v${Version}..." -ForegroundColor Cyan
    Write-Host "  [1/2] Creating release with app-release.apk..." -ForegroundColor Cyan
    & gh release create "v${Version}" "$releaseApkPath" --title "Melody v${Version}" --notes "$Changelog"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "gh release create failed (exit $LASTEXITCODE)!"
        exit 1
    }

    Write-Host "  [2/2] Uploading melody-debug.apk..." -ForegroundColor Cyan
    & gh release upload "v${Version}" "$debugApkPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "gh release upload failed (exit $LASTEXITCODE)!"
        exit 1
    }

    Write-Host "`n[SUCCESS] Release published to GitHub! Assets uploaded sequentially: app-release.apk (1st), melody-debug.apk (2nd)." -ForegroundColor Green
    exit 0
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
