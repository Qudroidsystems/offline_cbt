# Builds the Windows installer:  dist\OfflineCBT-Setup-<version>.exe
#
# Needs (on Windows): Flutter stable 3.38+, Visual Studio 2022 with "Desktop development with C++",
# Inno Setup 6 (https://jrsoftware.org/isdl.php). Or let GitHub build it: .github/workflows/build-windows.yml
#
#   powershell -ExecutionPolicy Bypass -File installer\build_windows.ps1
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
Set-Location $root

# ── version: pubspec.yaml is the source of truth ──────────────────────────
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$appConst = (Select-String -Path lib\app\services.dart -Pattern "const appVersion = '([0-9.]+)'").Matches[0].Groups[1].Value
if ($version -ne $appConst) { throw "Version mismatch: pubspec.yaml says $version but lib/app/services.dart says $appConst. Make them the same." }
Write-Host "Building Offline CBT $version"

# ── Windows runner (created once, then branded) ───────────────────────────
if (-not (Test-Path "windows\runner")) {
    Write-Host "Creating the Windows runner..."
    flutter create --platforms=windows --org ng.qudroid --project-name offline_cbt .
}
Copy-Item installer\assets\app_icon.ico windows\runner\resources\app_icon.ico -Force
$utf8 = New-Object System.Text.UTF8Encoding($false)   # no BOM (the resource compiler dislikes it)
$rc = (Resolve-Path "windows\runner\Runner.rc").Path
$rcText = (Get-Content $rc -Raw) `
    -replace 'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "Qudroid Systems"' `
    -replace 'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Offline CBT"' `
    -replace 'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "Offline CBT"' `
    -replace 'VALUE "LegalCopyright", "[^"]*"', ('VALUE "LegalCopyright", "Copyright (C) ' + (Get-Date).Year + ' Qudroid Systems"')
[System.IO.File]::WriteAllText($rc, $rcText, $utf8)
$main = (Resolve-Path "windows\runner\main.cpp").Path
[System.IO.File]::WriteAllText($main, ((Get-Content $main -Raw) -replace 'L"offline_cbt"', 'L"Offline CBT"'), $utf8)

# ── test, build, package ──────────────────────────────────────────────────
flutter pub get
Push-Location packages\cbt_core
dart pub get
dart run test/run_all.dart
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Core tests failed — not building." }
Pop-Location

flutter build windows --release --build-name $version
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php" }
& $iscc "/DAppVersion=$version" installer\offline_cbt.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
Write-Host "`nDone: dist\OfflineCBT-Setup-$version.exe — install it on the exam server and on every student computer."
