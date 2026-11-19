# GitHub Actions debug-preview installer (Windows PowerShell 5.1 compatible).
# Only older, disposable ir.example.medication_companion.m4rNNN previews
# are removed, and ONLY after the selected CI APK is verified and launched.
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

function Get-ObsoletePreviewPackages {
    param(
        [Parameter(Mandatory = $true)][string[]]$Installed,
        [Parameter(Mandatory = $true)][string]$Keep
    )
    if ($Keep -notmatch '^ir\.example\.medication_companion\.m4r([0-9]+)$') {
        throw 'The selected app is not a numbered medication CI preview'
    }
    $keepRun = [long]$Matches[1]
    $obsolete = @()
    foreach ($item in $Installed) {
        if ($item -match '^\s*package:(ir\.example\.medication_companion\.m4r([0-9]+))\s*$') {
            $oldRun = [long]$Matches[2]
            if ($oldRun -lt $keepRun) { $obsolete += $Matches[1] }
        }
    }
    return @($obsolete | Sort-Object -Unique)
}

if ($SelfTest) {
    $fixtures = @(
        'package:ir.example.medication_companion.m4r89',
        'package:ir.example.medication_companion.m4r91',
        'package:ir.example.medication_companion.m4r102',
        'package:ir.example.medication_companion.m4r103',
        'package:ir.example.medication_companion',
        'package:com.other.application',
        'package:ir.example.medication_companion.m4r102.attacker'
    )
    $obsolete = @(Get-ObsoletePreviewPackages -Installed $fixtures -Keep 'ir.example.medication_companion.m4r102')
    if ($obsolete.Count -ne 2 -or
        $obsolete[0] -ne 'ir.example.medication_companion.m4r89' -or
        $obsolete[1] -ne 'ir.example.medication_companion.m4r91') {
        throw "Unsafe preview selection: $($obsolete -join ',')"
    }
    $rejected = $false
    try {
        Get-ObsoletePreviewPackages -Installed $fixtures -Keep 'ir.example.medication_companion' | Out-Null
    } catch { $rejected = $true }
    if (!$rejected) { throw 'The base app must never be accepted as a CI target' }
    Write-Host 'PASS: old-only, exact-package, base-app-safe cleanup filter' -ForegroundColor Green
    return
}

& {
    $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    $device = 'emulator-5554'
    if (!(Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'ADB not found in Android SDK' }
    & $adb start-server | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not start ADB' }
    $devices = (& $adb devices) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $devices -notmatch '(?m)^emulator-5554\s+device\s*$') {
        throw "Emulator is not ready. ADB output: $devices"
    }

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select Medication Companion CI preview APK or ZIP'
    $dialog.InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
    $dialog.Filter = 'APK or ZIP (*.apk;*.zip)|*.apk;*.zip'
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No APK/ZIP selected' }
    $apk = $dialog.FileName

    if ([IO.Path]::GetExtension($apk).ToLowerInvariant() -eq '.zip') {
        $extract = Join-Path $env:TEMP ('medication-ci-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $extract -ItemType Directory -Force | Out-Null
        Expand-Archive -LiteralPath $apk -DestinationPath $extract -Force
        $apks = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter '*.apk')
        if ($apks.Count -ne 1) { throw "ZIP must contain exactly one APK. Found $($apks.Count)" }
        $apk = $apks[0].FullName
    }
    if (!(Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'APK not found' }
    $buildTools = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools'
    if (!(Test-Path -LiteralPath $buildTools -PathType Container)) { throw 'Android build-tools not found' }
    $aapt = Get-ChildItem -LiteralPath $buildTools -Recurse -File -Filter 'aapt.exe' |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (!$aapt) { throw 'Android aapt.exe not found' }
    $info = @(& $aapt.FullName dump badging $apk)
    if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect APK identity' }
    $packageFound = [regex]::Match(($info -join "`n"), "package:\s+name='([^']+)'").Groups[1].Value
    if ($packageFound -notmatch '^ir\.example\.medication_companion\.m4r[0-9]+$') {
        throw "Refusing to install a non-CI package: $packageFound"
    }
    $expected = $packageFound

    Write-Host "Verified preview APK: $expected" -ForegroundColor Green
    & $adb -s $device install -r --no-streaming $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
    $packages = @(& $adb -s $device shell pm list packages)
    if ($LASTEXITCODE -ne 0 -or (($packages -join "`n") -notmatch ('(?m)^package:' + [regex]::Escape($expected) + '\s*$'))) {
        throw 'Installation is not verified'
    }
    $launch = @(& $adb -s $device shell monkey -p $expected -c android.intent.category.LAUNCHER 1)
    if ($LASTEXITCODE -ne 0 -or (($launch -join "`n") -notmatch 'Events injected:\s*1')) {
        throw 'Installed app could not be launched'
    }
    Write-Host "SUCCESS - running package: $expected" -ForegroundColor Green

    # Delete only strictly older CI preview IDs. No base app, unrelated
    # package or newer preview can ever match the removal candidate set.
    $installed = @(& $adb -s $device shell pm list packages)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect installed CI previews' }
    $oldPreviews = @(Get-ObsoletePreviewPackages -Installed $installed -Keep $expected)
    foreach ($oldPackage in $oldPreviews) {
        $result = @(& $adb -s $device uninstall $oldPackage)
        if ($LASTEXITCODE -ne 0 -or (($result -join "`n") -notmatch '(?m)^Success\s*$')) {
            throw "Could not remove old preview $oldPackage; other apps were left installed"
        }
        Write-Host "Removed disposable old preview: $oldPackage" -ForegroundColor Cyan
    }
    Write-Host "CLEANUP OK - removed $($oldPreviews.Count) old CI preview(s)" -ForegroundColor Green
}
