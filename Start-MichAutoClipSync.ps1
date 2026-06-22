param([int]$Port=18765,[int]$PhonePort=8765,[int]$BeaconPort=18766,[int]$IntervalMs=400,[string]$LogPath)
$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $LogPath){ $LogPath=Join-Path $Root 'artifacts\proof\sync-runner.log' }
$StateDir=Split-Path -Path $LogPath
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$HostState=Join-Path $StateDir 'phone-base-url.txt'
function Log([string]$s){ Add-Content -Path $LogPath -Value ('{0:o} {1}' -f (Get-Date),$s) }
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
function Get-WinClip(){ try { $t=[System.Windows.Forms.Clipboard]::GetText(); if($null -eq $t){return ''}; return $t } catch { return '' } }
function Set-WinClip([string]$Text){ if([string]::IsNullOrEmpty($Text)){return}; try{ [System.Windows.Forms.Clipboard]::SetText($Text) }catch{} }
function Get-WinClipImageBytes(){ try { if(-not [System.Windows.Forms.Clipboard]::ContainsImage()){ return $null }; $img=[System.Windows.Forms.Clipboard]::GetImage(); if($null -eq $img){ return $null }; $ms=New-Object IO.MemoryStream; $img.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png); return $ms.ToArray() } catch { return $null } }
function Set-WinClipImageBytes([byte[]]$Bytes){ try { if($null -eq $Bytes -or $Bytes.Length -eq 0){return}; $ms=New-Object IO.MemoryStream(,$Bytes); $img=[System.Drawing.Image]::FromStream($ms); [System.Windows.Forms.Clipboard]::SetImage($img) } catch {} }
function HashBytes([byte[]]$Bytes){ if($null -eq $Bytes -or $Bytes.Length -eq 0){return ''}; $sha=[Security.Cryptography.SHA256]::Create(); (($sha.ComputeHash($Bytes)|ForEach-Object{$_.ToString('x2')}) -join '') }
function Invoke-Phone([string]$Base,[string]$Method,[string]$Path,[string]$Body,[int]$TimeoutMs=1500){
  $req=[System.Net.HttpWebRequest]::Create("$Base$Path"); $req.Timeout=$TimeoutMs; $req.ReadWriteTimeout=$TimeoutMs; $req.Method=$Method; $req.Proxy=$null
  if($Method -eq 'POST'){
    $bytes=[Text.Encoding]::UTF8.GetBytes($Body); $req.ContentType='text/plain; charset=utf-8'; $req.ContentLength=$bytes.Length
    $st=$req.GetRequestStream(); $st.Write($bytes,0,$bytes.Length); $st.Close()
  }
  $res=$req.GetResponse(); try { $sr=New-Object IO.StreamReader($res.GetResponseStream(),[Text.Encoding]::UTF8); $txt=$sr.ReadToEnd(); $sr.Close(); return $txt } finally { $res.Close() }
}
function Invoke-PhoneBytes([string]$Base,[string]$Method,[string]$Path,[byte[]]$Body,[int]$TimeoutMs=3000){
  $req=[System.Net.HttpWebRequest]::Create("$Base$Path"); $req.Timeout=$TimeoutMs; $req.ReadWriteTimeout=$TimeoutMs; $req.Method=$Method; $req.Proxy=$null
  if($Method -eq 'POST'){
    $req.ContentType='image/png'; $req.ContentLength=$Body.Length
    $st=$req.GetRequestStream(); $st.Write($Body,0,$Body.Length); $st.Close()
  }
  $res=$req.GetResponse(); try { $ms=New-Object IO.MemoryStream; $res.GetResponseStream().CopyTo($ms); return $ms.ToArray() } finally { $res.Close() }
}
function Get-PhoneStatus([string]$Base){ try { return (Invoke-Phone $Base 'GET' '/status' '' 1200) | ConvertFrom-Json } catch { return $null } }
function Test-Base([string]$Base,[int]$TimeoutMs=800){
  if([string]::IsNullOrWhiteSpace($Base)){ return $false }
  try { $s=Invoke-Phone $Base 'GET' '/status' '' $TimeoutMs; return ($s -match '"ok"\s*:\s*true') } catch { return $false }
}
function Save-Base([string]$Base){ if(Test-Base $Base 1000){ Set-Content -Path $HostState -Value $Base -Encoding ASCII; Log "PHONE_BASE=$Base"; return $true }; return $false }
function Receive-Beacon([int]$Seconds){
  $client=$null
  try{
    $client=New-Object Net.Sockets.UdpClient($BeaconPort); $client.Client.ReceiveTimeout=500
    $end=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0); $stop=(Get-Date).AddSeconds($Seconds)
    while((Get-Date) -lt $stop){
      try{ $bytes=$client.Receive([ref]$end); $msg=[Text.Encoding]::UTF8.GetString($bytes); if($msg -like 'MICH_AUTO_CLIP_SYNC*'){ $base='http://'+$end.Address.IPAddressToString+':'+$PhonePort; if(Save-Base $base){ return $base } } }catch{}
    }
  }catch{ Log ('BEACON_LISTEN_ERR '+$_.Exception.Message) }
  try{ if($client){$client.Close()} }catch{}
  return $null
}
function Get-CandidateIps(){
  $set=New-Object 'System.Collections.Generic.HashSet[string]'
  try{ Get-NetNeighbor -AddressFamily IPv4 -State Reachable,Stale,Delay,Probe -ErrorAction SilentlyContinue | ForEach-Object { if($_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'){ [void]$set.Add($_.IPAddress) } } }catch{}
  try{
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' -and $_.PrefixLength -ge 24 } | Select-Object -First 3 | ForEach-Object {
      $parts=$_.IPAddress.Split('.'); $prefix=($parts[0..2] -join '.'); 1..254 | ForEach-Object { [void]$set.Add("$prefix.$_") }
    }
  }catch{}
  return @($set)
}
function Discover-Base([string]$Reason){
  Log "DISCOVER reason=$Reason"
  $cands=@()
  if(Test-Path $HostState){ $cands += (Get-Content -Path $HostState -ErrorAction SilentlyContinue | Select-Object -First 1) }
  $cands += 'http://127.0.0.1:'+ $Port
  foreach($b in $cands){ if(Save-Base $b){ return $b } }
  $b=Receive-Beacon 3; if($b){ return $b }
  foreach($ip in Get-CandidateIps){ $b='http://'+$ip+':'+$PhonePort; if(Save-Base $b){ return $b } }
  return $null
}
function Optional-Adb-Kick(){
  try{
    $Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'; if(-not(Test-Path $Adb)){return}
    $devs=& $Adb devices | Out-String
    $serial=(($devs -split "`r?`n" | Where-Object { $_ -match '\tdevice$' -or $_ -match '\sdevice\s' } | Select-Object -First 1) -replace '\s+device.*$','')
    if(-not $serial){ return }
    Log "ADB_OPTIONAL_SERIAL=$serial"
    try { & $Adb -s $serial forward --remove tcp:$Port 2>$null | Out-Null } catch {}
    & $Adb -s $serial forward tcp:$Port tcp:$PhonePort | Out-Null
    & $Adb -s $serial shell am start-foreground-service -n com.mich.autoclipsync/.ClipBridgeService 2>$null | Out-Null
    Save-Base ('http://127.0.0.1:'+ $Port) | Out-Null
  }catch{ Log ('ADB_OPTIONAL_ERR '+$_.Exception.Message) }
}
Log 'START LAN_PRIMARY_NO_DEBUG_REQUIRED'
$base=Discover-Base 'startup'
if(-not $base){ Optional-Adb-Kick; $base=Discover-Base 'after_optional_adb' }
$lastPc=Get-WinClip
$lastPhone=''
if($base){ try{ $lastPhone=Invoke-Phone $base 'GET' '/clip' '' 1200 }catch{} }
$lastPcImageHash=HashBytes (Get-WinClipImageBytes)
$st=if($base){Get-PhoneStatus $base}else{$null}
$lastPhoneImageHash=if($st){[string]$st.imageHash}else{''}
Log ('INIT base='+$base+' pcLen='+$lastPc.Length+' phoneLen='+$lastPhone.Length+' pcImageHash='+$lastPcImageHash+' phoneImageHash='+$lastPhoneImageHash)
$failCount=0
while($true){
  try{
    if(-not $base -or -not(Test-Base $base 700)){ $base=Discover-Base 'loop_missing_or_failed'; if(-not $base){ Optional-Adb-Kick; $base=Discover-Base 'loop_after_optional_adb' } }
    if($base){
      $st=Get-PhoneStatus $base
      $phoneImageHash=if($st){[string]$st.imageHash}else{''}
      $pcImageBytes=Get-WinClipImageBytes
      $pcImageHash=HashBytes $pcImageBytes
      if($phoneImageHash -and $phoneImageHash -ne $lastPhoneImageHash -and $phoneImageHash -ne $pcImageHash){
        $img=Invoke-PhoneBytes $base 'GET' '/image' $null 3000
        if($img.Length -gt 0){ Set-WinClipImageBytes $img; $lastPhoneImageHash=$phoneImageHash; $lastPcImageHash=HashBytes (Get-WinClipImageBytes); Log ('PHONE_IMAGE_TO_PC base='+$base+' bytes='+$img.Length+' hash='+$phoneImageHash+' pcHash='+$lastPcImageHash); Start-Sleep -Milliseconds $IntervalMs; continue }
      }
      if($pcImageHash -and $pcImageHash -ne $lastPcImageHash -and $pcImageHash -ne $lastPhoneImageHash){
        Invoke-PhoneBytes $base 'POST' '/image' $pcImageBytes 3000 | Out-Null
        $lastPcImageHash=$pcImageHash; $lastPhoneImageHash=$pcImageHash; Log ('PC_IMAGE_TO_PHONE base='+$base+' bytes='+$pcImageBytes.Length+' hash='+$pcImageHash); Start-Sleep -Milliseconds $IntervalMs; continue
      }
      $ph=Invoke-Phone $base 'GET' '/clip' '' 1200; if($null -eq $ph){$ph=''}
      $pc=Get-WinClip
      $failCount=0
      if(-not [string]::IsNullOrEmpty($ph) -and $ph -ne $lastPhone -and $ph -ne $pc){ Set-WinClip $ph; $lastPhone=$ph; $lastPc=$ph; Log ('PHONE_TO_PC base='+$base+' len='+$ph.Length); Start-Sleep -Milliseconds $IntervalMs; continue }
      if(-not [string]::IsNullOrEmpty($pc) -and $pc -ne $lastPc -and $pc -ne $lastPhone){ Invoke-Phone $base 'POST' '/clip' $pc 1500 | Out-Null; $lastPc=$pc; $lastPhone=$pc; Log ('PC_TO_PHONE base='+$base+' len='+$pc.Length) }
      if($pc -eq $lastPhone){ $lastPc=$pc }
      if($pcImageHash -eq $lastPhoneImageHash){ $lastPcImageHash=$pcImageHash }
    }
  } catch {
    $failCount++; Log ('ERR count='+$failCount+' '+$_.Exception.Message); if($failCount -eq 1 -or $failCount % 5 -eq 0){ $base=Discover-Base "error_$failCount" }
  }
  Start-Sleep -Milliseconds $IntervalMs
}
