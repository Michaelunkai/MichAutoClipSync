$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms | Out-Null
function Get-WinClip(){try{[System.Windows.Forms.Clipboard]::GetText()}catch{''}}
function Set-WinClip($t){[System.Windows.Forms.Clipboard]::SetText($t)}
function Clip(){(Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:18765/clip).Content}
function CenterFromBounds([string]$b){ if($b -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]'){ return @([int](([int]$Matches[1]+[int]$Matches[3])/2),[int](([int]$Matches[2]+[int]$Matches[4])/2))}; return @(280,2110) }
$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'
$devs=& $Adb devices | Out-String
$S=($devs -split "`r?`n" | ? { $_ -match '\sdevice\s|\tdevice$' } | Select-Object -First 1) -replace '\s+device.*$',''
if(-not $S){ Write-Host 'NO_ADB_DEVICE'; exit 2 }
Write-Host '=== device/package/process/status ==='
& $Adb -s $S shell getprop ro.product.model
& $Adb -s $S shell getprop ro.build.version.release
& $Adb -s $S shell pm path com.mich.autoclipsync
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Select ProcessName,Id,Path | Format-List
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*Start-MichAutoClipSync.ps1*' } | Select ProcessId,CommandLine | Format-List
& $Adb -s $S forward tcp:18765 tcp:8765 | Out-Null
& $Adb -s $S shell settings put secure enabled_accessibility_services 'com.mich.autoclipsync/com.mich.autoclipsync.ClipAccessibilityService'
& $Adb -s $S shell settings put secure accessibility_enabled 1
Write-Host 'ACCESSIBILITY='; & $Adb -s $S shell settings get secure enabled_accessibility_services
Write-Host 'STATUS='; Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:18765/status | % Content
Write-Host '=== Windows to Android ==='
$pc='MICH_PC2ANDROID_'+([guid]::NewGuid().ToString('N'))
Set-WinClip $pc; $ok1=$false;$b=''
for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 400;$b=Clip;if($b -eq $pc){$ok1=$true;break}}
Write-Host "PC_TO_ANDROID_SENTINEL=$pc`nANDROID_BRIDGE_CLIP=$b`nPC_TO_ANDROID_OK=$ok1"
Write-Host '=== Android companion UI copy to Windows ==='
$and='MICH_ANDROIDCOPY_'+([guid]::NewGuid().ToString('N'))
Set-WinClip 'MICH_WIN_BASE'
Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Post -Uri http://127.0.0.1:18765/clip -Body ([Text.Encoding]::UTF8.GetBytes('MICH_PHONE_BASE')) -ContentType 'text/plain; charset=utf-8' | Out-Null
& $Adb -s $S shell am start -S -n com.mich.autoclipsync/.MainActivity --es seed_text $and | Out-Null
Start-Sleep -Seconds 2
$focus=& $Adb -s $S shell dumpsys window | Select-String -Pattern 'mCurrentFocus|mFocusedApp' | Out-String
Write-Host $focus
$phoneXml='/sdcard/mich_autoclip_verify.xml'; $pcXml=Join-Path $Root 'artifacts\proof\mich_autoclip_verify.xml'
& $Adb -s $S shell uiautomator dump $phoneXml | Out-Null
& $Adb -s $S pull $phoneXml $pcXml | Out-Null
[xml]$xml=Get-Content -Raw $pcXml
$copyNode=$xml.SelectNodes('//node') | ? { $_.text -eq 'Copy field' -and $_.enabled -eq 'true' } | Select-Object -First 1
if($copyNode){ $xy=CenterFromBounds $copyNode.bounds; Write-Host "COPY_BUTTON_BOUNDS=$($copyNode.bounds) TAP=$($xy[0]),$($xy[1])"; & $Adb -s $S shell input tap $xy[0] $xy[1] | Out-Null } else { Write-Host 'COPY_BUTTON_NOT_FOUND'; }
$ok2=$false;$w='';$status=''
for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 400;$w=Get-WinClip;try{$status=(Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:18765/status).Content}catch{};if($w -eq $and){$ok2=$true;break}}
Write-Host "ANDROID_COPY_SENTINEL=$and`nWINDOWS_CLIP=$w`nBRIDGE_STATUS=$status`nANDROID_COMPANION_COPY_TO_WINDOWS_OK=$ok2"
if($ok1 -and $ok2){exit 0}else{exit 1}
