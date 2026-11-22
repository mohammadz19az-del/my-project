<#
  Tesla.org - one-time project setup and verification for Windows (PowerShell).

  Run from the project folder:   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
  Options:  -Build   also build the Windows and Android release versions
            -SkipTests  skip "flutter test"
            -PrepareOnly  only generate/patch the native folders, then stop (used by the cloud build)

  What it does
   1. Generates the native android/ and windows/ folders (flutter create) if missing.
   2. Removes the sample widget test that flutter create adds (it does not match this app).
   3. Android: sets minSdk 23 (needed by secure storage) and adds the INTERNET permission
      to the main manifest (flutter create only adds it for debug builds).
   4. flutter pub get, flutter analyze, flutter test (and builds with -Build).
  Nothing here is hidden: every step prints what it does. Requires Flutter on PATH.
#>
param([switch]$Build, [switch]$SkipTests, [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step 'Checking Flutter'
flutter --version

if (-not ((Test-Path 'android') -and (Test-Path 'windows'))) {
  Step 'Generating android/ and windows/ folders'
  flutter create --platforms=windows,android --project-name tesla_org --org org.teslaorg .
} else { Write-Host 'android/ and windows/ already exist - skipping flutter create' }

if (Test-Path 'test\widget_test.dart') {
  Step 'Removing the sample widget_test.dart created by flutter create'
  Remove-Item 'test\widget_test.dart'
}

Step 'Configuring Android (minSdk 23 + INTERNET permission)'
$gradle = Get-ChildItem 'android\app' -Filter 'build.gradle*' | Select-Object -First 1
if ($gradle) {
  $text = Get-Content $gradle.FullName -Raw
  $patched = $text -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
  $patched = $patched -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
  $patched = $patched -replace 'minSdkVersion\s*=\s*flutter\.minSdkVersion', 'minSdkVersion = 23'
  if ($patched -ne $text) { Set-Content $gradle.FullName $patched -NoNewline; Write-Host "minSdk set to 23 in $($gradle.Name)" }
  elseif ($text -match 'minSdk(Version)?\s*=?\s*2[3-9]|minSdk(Version)?\s*=?\s*[3-9]\d') { Write-Host 'minSdk already >= 23' }
  else { Write-Warning "Could not find minSdk in $($gradle.Name). Set it to 23 manually." }
}
$manifest = 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
  $m = Get-Content $manifest -Raw
  if ($m -notmatch 'android.permission.INTERNET') {
    $m = $m -replace '<application', "<uses-permission android:name=`"android.permission.INTERNET`"/>`n    <application"
    Set-Content $manifest $m -NoNewline
    Write-Host 'INTERNET permission added to the main manifest'
  } else { Write-Host 'INTERNET permission already present' }
}

if ($PrepareOnly) { Write-Host 'Native folders prepared.'; return }

Step 'flutter pub get';  flutter pub get
Step 'flutter analyze';  flutter analyze
if (-not $SkipTests) { Step 'flutter test'; flutter test }
if ($Build) {
  Step 'Building Windows release'; flutter build windows --release
  Step 'Building Android release APK'; flutter build apk --release
}
Write-Host "`nDone. Run the app with:  flutter run -d windows" -ForegroundColor Green
