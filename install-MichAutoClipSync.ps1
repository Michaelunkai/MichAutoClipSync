param([switch]$SkipBuild)
$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $SkipBuild){ & (Join-Path $Root 'build-tray.ps1'); if($LASTEXITCODE -ne 0){throw 'tray build failed'}; & (Join-Path $Root 'build-android.ps1'); if($LASTEXITCODE -ne 0){throw 'android build failed'} }
$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'
try { Load-FullPowerShellProfile } catch {}
aadb devices -l; aadb connect; aadb devices -l
$devs=& $Adb devices | Out-String
$S=($devs -split "`r?`n" | ? { $_ -match '\sdevice\s|\tdevice$' } | Select-Object -First 1) -replace '\s+device.*$',''
if(-not $S){throw 'No authorized Android ADB device'}
$Apk=Join-Path $Root 'artifacts\build-output\MichAutoClipSync-debug.apk'
& $Adb -s $S install -r $Apk
& $Adb -s $S shell am start -n com.mich.autoclipsync/.MainActivity
& $Adb -s $S shell am start-foreground-service -n com.mich.autoclipsync/.ClipBridgeService
$svc='com.mich.autoclipsync/com.mich.autoclipsync.ClipAccessibilityService'
& $Adb -s $S shell appops set com.mich.autoclipsync READ_CLIPBOARD allow 2>$null
& $Adb -s $S shell appops set com.mich.autoclipsync WRITE_CLIPBOARD allow 2>$null
& $Adb -s $S shell settings put secure enabled_accessibility_services $svc
& $Adb -s $S shell settings put secure accessibility_enabled 1
# Replace prior task and launch final repo-local tray EXE.
$Task='MichAutoClipSync Tray'
cmd /c "schtasks /Delete /TN `"$Task`" /F 2>nul" | Out-Null
$Exe=Join-Path $Root 'MichAutoClipSyncTray.exe'
cmd /c "schtasks /Create /F /TN `"$Task`" /SC ONLOGON /RL LIMITED /TR `"$Exe`""
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | % { Stop-Process -Id $_.ProcessId -Force }
Start-Process -FilePath $Exe -WorkingDirectory $Root
Start-Sleep -Seconds 8
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Select ProcessName,Id,Path | Format-List
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | Select ProcessId,CommandLine | Format-List
schtasks /Query /TN "$Task" /FO LIST /V
try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:18765/status | % Content } catch { Write-Host "STATUS_FAIL $($_.Exception.Message)" }
