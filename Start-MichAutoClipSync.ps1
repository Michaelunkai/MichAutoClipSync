param([int]$Port=18765,[int]$PhonePort=8765,[int]$IntervalMs=400,[string]$LogPath)
$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $LogPath){ $LogPath=Join-Path $Root 'artifacts\proof\sync-runner.log' }
New-Item -ItemType Directory -Force -Path (Split-Path -Path $LogPath) | Out-Null
function Log($s){ $line=('{0:o} {1}' -f (Get-Date),$s); Add-Content -Path $LogPath -Value $line; Write-Host $line }
Add-Type -AssemblyName System.Windows.Forms | Out-Null
function Get-WinClip(){ try { $t=[System.Windows.Forms.Clipboard]::GetText(); if($null -eq $t){return ''}; return $t } catch { return '' } }
function Set-WinClip([string]$Text){ if([string]::IsNullOrEmpty($Text)){return}; [System.Windows.Forms.Clipboard]::SetText($Text) }
function Phone([string]$Method,[string]$Path,[string]$Body){ $uri="http://127.0.0.1:$Port$Path"; if($Method -eq 'POST'){ return Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Post -Uri $uri -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -ContentType 'text/plain; charset=utf-8' }; return Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Get -Uri $uri }
try { Load-FullPowerShellProfile } catch {}
$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'
Log 'START'
try { aadb connect | Out-String | % { Log $_ } } catch { Log ('AADB_CONNECT_ERR '+$_.Exception.Message) }
$devs=& $Adb devices | Out-String
$serial=($devs -split "`r?`n" | Where-Object { $_ -match '\tdevice$' -or $_ -match '\sdevice\s' } | Select-Object -First 1) -replace '\s+device.*$',''
if(-not $serial){ Log 'NO_ADB_DEVICE'; Start-Sleep -Seconds 30; exit 2 }
Log "SERIAL=$serial"
& $Adb -s $serial shell am start-foreground-service -n com.mich.autoclipsync/.ClipBridgeService | Out-String | % { Log $_ }
& $Adb -s $serial shell monkey -p com.mich.autoclipsync -c android.intent.category.LAUNCHER 1 | Out-String | % { Log $_ }
Start-Sleep -Seconds 1
& $Adb -s $serial forward --remove-all | Out-Null
& $Adb -s $serial forward tcp:$Port tcp:$PhonePort | Out-String | % { Log $_ }
try { Phone GET '/status' '' | % Content | % { Log ('STATUS '+$_) } } catch { Log ('STATUS_ERR '+$_.Exception.Message) }
$lastPc=Get-WinClip; try { $lastPhone=(Phone GET '/clip' '').Content; if($null -eq $lastPhone){$lastPhone=''} } catch { $lastPhone='' }
Log ('INIT pcLen='+$lastPc.Length+' phoneLen='+$lastPhone.Length)
while($true){ try{ $ph=(Phone GET '/clip' '').Content; if($null -eq $ph){$ph=''}; $pc=Get-WinClip; if(-not [string]::IsNullOrEmpty($ph) -and $ph -ne $lastPhone -and $ph -ne $pc){ Set-WinClip $ph; $lastPhone=$ph; $lastPc=$ph; Log ('PHONE_TO_PC len='+$ph.Length); Start-Sleep -Milliseconds $IntervalMs; continue }; if(-not [string]::IsNullOrEmpty($pc) -and $pc -ne $lastPc -and $pc -ne $lastPhone){ Phone POST '/clip' $pc | Out-Null; $lastPc=$pc; $lastPhone=$pc; Log ('PC_TO_PHONE len='+$pc.Length) }; if($pc -eq $lastPhone){ $lastPc=$pc } } catch { Log ('ERR '+$_.Exception.Message); try{ & $Adb -s $serial forward tcp:$Port tcp:$PhonePort | Out-Null }catch{} }; Start-Sleep -Milliseconds $IntervalMs }
