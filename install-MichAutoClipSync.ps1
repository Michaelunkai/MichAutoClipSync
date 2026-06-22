param([switch]$SkipBuild)
$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe=Join-Path $Root 'MichAutoClipSyncTray.exe'
$Runner=Join-Path $Root 'Start-MichAutoClipSync.ps1'
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | % { Stop-Process -Id $_.ProcessId -Force }
if(-not $SkipBuild){ & (Join-Path $Root 'build-tray.ps1'); if($LASTEXITCODE -ne 0){throw 'tray build failed'}; & (Join-Path $Root 'build-android.ps1'); if($LASTEXITCODE -ne 0){throw 'android build failed'} }
$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'
try { Load-FullPowerShellProfile } catch {}
try {
  if(Get-Command aadb -ErrorAction SilentlyContinue){
    aadb devices -l
    aadb connect
    aadb devices -l
  }
} catch {
  Write-Host "AADB_OPTIONAL_SKIP $($_.Exception.Message)"
}
$devs=& $Adb devices | Out-String
$S=(($devs -split "`r?`n" | ? { $_ -match '\sdevice(\s|$)' -and $_ -notmatch 'offline' -and $_ -notmatch '\(2\)' -and $_ -notmatch '^192\.168\.' } | Select-Object -First 1) -replace '\s+device.*$','')
if(-not $S){ $S=(($devs -split "`r?`n" | ? { $_ -match '\sdevice(\s|$)' -and $_ -notmatch 'offline' -and $_ -notmatch '^192\.168\.' } | Select-Object -First 1) -replace '\s+device.*$','') }
if(-not $S){throw 'No authorized Android ADB device'}
$Apk=Join-Path $Root 'artifacts\build-output\MichAutoClipSync-debug.apk'
& $Adb -s $S install -r $Apk
foreach($perm in @('android.permission.READ_EXTERNAL_STORAGE','android.permission.READ_MEDIA_IMAGES','android.permission.POST_NOTIFICATIONS')){
  & $Adb -s $S shell pm grant com.mich.autoclipsync $perm 2>$null | Out-Null
}
& $Adb -s $S shell am start -n com.mich.autoclipsync/.MainActivity
& $Adb -s $S shell am start-foreground-service -n com.mich.autoclipsync/.ClipBridgeService
$svc='com.mich.autoclipsync/com.mich.autoclipsync.ClipAccessibilityService'
& $Adb -s $S shell appops set com.mich.autoclipsync READ_CLIPBOARD allow 2>$null
& $Adb -s $S shell appops set com.mich.autoclipsync WRITE_CLIPBOARD allow 2>$null
$enabledRaw=(& $Adb -s $S shell settings get secure enabled_accessibility_services 2>$null | Out-String).Trim()
if([string]::IsNullOrWhiteSpace($enabledRaw) -or $enabledRaw -eq 'null'){
  $enabledNew=$svc
} elseif(($enabledRaw -split ':') -contains $svc){
  $enabledNew=$enabledRaw
} else {
  $enabledNew="$enabledRaw`:$svc"
}
& $Adb -s $S shell settings put secure enabled_accessibility_services $enabledNew
& $Adb -s $S shell settings put secure accessibility_enabled 1
# Replace prior task and launch final repo-local tray EXE.
$Task='MichAutoClipSync Tray'
cmd /c "schtasks /Delete /TN `"$Task`" /F 2>nul" | Out-Null
cmd /c "schtasks /Create /F /TN `"$Task`" /SC ONLOGON /RL LIMITED /TR `"$Exe`""
cmd /c "schtasks /Change /TN `"$Task`" /ENABLE" | Out-Null
function Set-TaskActionCom([string]$Path,[string]$Command,[string]$Arguments,[string]$WorkingDirectory,[string]$Description){
  try{
    $svc=New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $lastSlash=$Path.LastIndexOf('\')
    if($lastSlash -le 0){$folderPath='\';$name=$Path.TrimStart('\')}else{$folderPath=$Path.Substring(0,$lastSlash);$name=$Path.Substring($lastSlash+1)}
    $folder=$svc.GetFolder($folderPath)
    $taskObj=$folder.GetTask($name)
    $def=$taskObj.Definition
    if($def.Actions.Count -lt 1){return}
    $a=$def.Actions.Item(1)
    $a.Path=$Command
    $a.Arguments=$Arguments
    $a.WorkingDirectory=$WorkingDirectory
    $def.RegistrationInfo.Description=$Description
    $def.Settings.Enabled=$true
    $null=$folder.RegisterTaskDefinition($name,$def,4,$null,$null,$def.Principal.LogonType)
    cmd /c "schtasks /Change /TN `"$Path`" /ENABLE" | Out-Null
  }catch{}
}
$StartupMasterExe='F:\study\Windows\Applications\Desktop\Utilities\System\Startup\Managers\mich-startup-master\build\MichStartupMaster.exe'
$QuietVbs='C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
if((Test-Path $StartupMasterExe) -and (Test-Path $QuietVbs)){
  $payload="C:\Windows\System32\wscript.exe`n//B //Nologo `"$QuietVbs`" `"$Exe`" 120 0 25"
  $payload64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
  Set-TaskActionCom '\MichStartupMaster\CustomStartup_MichAutoClipSyncTray_6ab3a629' $StartupMasterExe "--tray-run $payload64" (Split-Path $StartupMasterExe -Parent) "Window-suppressed startup target: $Exe"
}
Set-TaskActionCom '\CustomStartup_MichAutoClipSyncTray_6ab3a629' $Exe '' $Root "Window-suppressed startup target: $Exe"
Set-TaskActionCom '\MichAutoClipSync Tray' $Exe '' $Root "MichAutoClipSync exact tray startup: $Exe"
try {
  Import-Module ScheduledTasks -ErrorAction Stop
  $Action=New-ScheduledTaskAction -Execute $Exe -WorkingDirectory $Root
  Get-ScheduledTask | Where-Object {
    $_.TaskName -eq $Task -or
    $_.TaskName -like 'CustomStartup_MichAutoClipSyncTray*' -or
    (($_.Actions | Out-String) -like '*MichAutoClipSync*')
  } | ForEach-Object {
    Set-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Action $Action | Out-Null
    Enable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | Out-Null
  }
} catch {}
& schtasks.exe /Change /TN 'MichAutoClipSync Tray' /ENABLE 2>$null | Out-Null
& schtasks.exe /Change /TN '\CustomStartup_MichAutoClipSyncTray_6ab3a629' /ENABLE 2>$null | Out-Null
& schtasks.exe /Change /TN '\MichStartupMaster\CustomStartup_MichAutoClipSyncTray_6ab3a629' /ENABLE 2>$null | Out-Null
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | % { Stop-Process -Id $_.ProcessId -Force }
Start-Process -FilePath $Exe -WorkingDirectory $Root
Start-Sleep -Seconds 8
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Select ProcessName,Id,Path | Format-List
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | Select ProcessId,CommandLine | Format-List
schtasks /Query /TN "$Task" /FO LIST /V
try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:18765/status | % Content } catch { Write-Host "STATUS_FAIL $($_.Exception.Message)" }
