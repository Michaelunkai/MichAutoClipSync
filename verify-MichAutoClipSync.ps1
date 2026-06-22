$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
function Get-WinClip(){try{[System.Windows.Forms.Clipboard]::GetText()}catch{''}}
function Set-WinClip($t){[System.Windows.Forms.Clipboard]::SetText($t)}
function Get-WinClipImageBytes(){try{if(-not [System.Windows.Forms.Clipboard]::ContainsImage()){return $null};$img=[System.Windows.Forms.Clipboard]::GetImage();$ms=New-Object IO.MemoryStream;$img.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png);$ms.ToArray()}catch{$null}}
function Set-WinClipImage([byte[]]$Bytes){$ms=New-Object IO.MemoryStream(,$Bytes);$img=[System.Drawing.Image]::FromStream($ms);[System.Windows.Forms.Clipboard]::SetImage($img)}
function HashBytes([byte[]]$Bytes){if($null -eq $Bytes -or $Bytes.Length -eq 0){return ''};$sha=[Security.Cryptography.SHA256]::Create();(($sha.ComputeHash($Bytes)|%{$_.ToString('x2')}) -join '')}
function Get-WinClipImageInfo(){try{if(-not [System.Windows.Forms.Clipboard]::ContainsImage()){return $null};$img=[System.Windows.Forms.Clipboard]::GetImage();if($null -eq $img){return $null};$bmp=New-Object System.Drawing.Bitmap($img);try{$px=$bmp.GetPixel(0,0);[pscustomobject]@{Width=$bmp.Width;Height=$bmp.Height;PixelRgb="$($px.R),$($px.G),$($px.B)";Hash=HashBytes (Get-WinClipImageBytes)}}finally{$bmp.Dispose();$img.Dispose()}}catch{$null}}
function New-TestPngBytes([int]$R,[int]$G,[int]$B){$bmp=New-Object Drawing.Bitmap 64,64;$gfx=[Drawing.Graphics]::FromImage($bmp);$gfx.Clear([Drawing.Color]::FromArgb($R,$G,$B));$gfx.FillEllipse([Drawing.Brushes]::White,8,8,48,48);$ms=New-Object IO.MemoryStream;$bmp.Save($ms,[Drawing.Imaging.ImageFormat]::Png);$gfx.Dispose();$bmp.Dispose();$ms.ToArray()}
function Invoke-Phone([string]$Base,[string]$Method,[string]$Path,[object]$Body=$null){
  $req=[Net.HttpWebRequest]::Create("$Base$Path");$req.Proxy=$null;$req.Timeout=3000;$req.ReadWriteTimeout=3000;$req.Method=$Method
  if($Method -eq 'POST'){
    if($Body -is [byte[]]){$bytes=$Body;$req.ContentType='image/png'}else{$bytes=[Text.Encoding]::UTF8.GetBytes([string]$Body);$req.ContentType='text/plain; charset=utf-8'}
    $req.ContentLength=$bytes.Length;$s=$req.GetRequestStream();$s.Write($bytes,0,$bytes.Length);$s.Close()
  }
  $res=$req.GetResponse();try{$ms=New-Object IO.MemoryStream;$res.GetResponseStream().CopyTo($ms);$bytes=$ms.ToArray();if($Path -eq '/image'){return $bytes};return [Text.Encoding]::UTF8.GetString($bytes)}finally{$res.Close()}
}
function Post-Image([string]$Base,[byte[]]$Bytes){
  $req=[Net.HttpWebRequest]::Create("$Base/image");$req.Proxy=$null;$req.Timeout=3000;$req.ReadWriteTimeout=3000;$req.Method='POST';$req.ContentType='image/png';$req.ContentLength=$Bytes.Length
  $s=$req.GetRequestStream();$s.Write($Bytes,0,$Bytes.Length);$s.Close()
  $res=$req.GetResponse();$res.Close()
}
function Status([string]$Base){(Invoke-Phone $Base GET '/status') | ConvertFrom-Json}
function Convert-StatusForProof($Status){
  if($null -eq $Status){return ''}
  $selection=[string]$Status.lastAccessibilitySelection
  ([pscustomobject]@{
    ok=$Status.ok
    transport=$Status.transport
    port=$Status.port
    lastSource=$Status.lastSource
    kind=$Status.kind
    length=$Status.length
    imageLength=$Status.imageLength
    imageHash=$Status.imageHash
    accessibilityRunning=$Status.accessibilityRunning
    accessibilityAgeMs=$Status.accessibilityAgeMs
    lastAccessibilitySource=$Status.lastAccessibilitySource
    lastAccessibilityError=$Status.lastAccessibilityError
    lastAccessibilityEvent=$Status.lastAccessibilityEvent
    lastAccessibilitySelectionLength=$selection.Length
    semClipboardAvailable=$Status.semClipboardAvailable
    semClipboardRunning=$Status.semClipboardRunning
    semClipboardAgeMs=$Status.semClipboardAgeMs
    semClipboardEventCount=$Status.semClipboardEventCount
    lastSemClipboardEvent=$Status.lastSemClipboardEvent
    lastSemClipboardEventArgs=$Status.lastSemClipboardEventArgs
    mediaImageObserverRunning=$Status.mediaImageObserverRunning
    mediaImageAgeMs=$Status.mediaImageAgeMs
    lastMediaImageSource=$Status.lastMediaImageSource
    lastMediaImageError=$Status.lastMediaImageError
    lastMediaImageNamePresent=(-not [string]::IsNullOrEmpty([string]$Status.lastMediaImageName))
  } | ConvertTo-Json -Compress)
}
function Wait-Accessibility([string]$Base){
  $latest=$null
  for($i=0;$i -lt 40;$i++){
    Start-Sleep -Milliseconds 500
    try{
      $latest=Status $Base
      if($latest.accessibilityRunning -eq $true -and [int64]$latest.accessibilityAgeMs -lt 5000){return $latest}
    }catch{}
  }
  return $latest
}
function Wait-LanBase(){
  $baseFile=Join-Path $Root 'artifacts\proof\phone-base-url.txt'
  for($i=0;$i -lt 60;$i++){
    Start-Sleep -Seconds 1
    $base=$null
    if(Test-Path $baseFile){$base=(Get-Content $baseFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()}
    if($base -and $base -notmatch '127\.0\.0\.1'){try{$st=Status $base;if($st.ok){return @($base,$st)}}catch{}}
  }
  return @($null,$null)
}
Write-Host '=== exact process and LAN status ==='
Get-Process MichAutoClipSyncTray -ErrorAction SilentlyContinue | Select ProcessName,Id,Path | Format-List
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -like '*MichAutoClipSync\Start-MichAutoClipSync.ps1*' } | Select ProcessId,CommandLine | Format-List
$pair=Wait-LanBase;$base=$pair[0];$status=$pair[1]
Write-Host "LAN_BASE=$base"
Write-Host "STATUS=$(Convert-StatusForProof $status)"
if(-not $base){Write-Host 'LAN_BASE_OK=False'; exit 2}
$status=Wait-Accessibility $base
$accessOk=($status.accessibilityRunning -eq $true -and [int64]$status.accessibilityAgeMs -lt 5000 -and [string]::IsNullOrEmpty([string]$status.lastAccessibilityError))
Write-Host "ACCESSIBILITY_STATUS=$(Convert-StatusForProof $status)"
Write-Host "ANDROID_BACKGROUND_OBSERVER_OK=$accessOk"
Write-Host '=== LAN Windows text to Android ==='
$pc='MICH_LAN_PC2ANDROID_'+([guid]::NewGuid().ToString('N'))
Set-WinClip $pc;$ok1=$false;$clip=''
for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 500;try{$clip=Invoke-Phone $base GET '/clip';if($clip -eq $pc){$ok1=$true;break}}catch{}}
Write-Host "PC_TO_ANDROID_SENTINEL=$pc`nANDROID_BRIDGE_CLIP=$clip`nLAN_PC_TO_ANDROID_OK=$ok1"
Write-Host '=== LAN Android text to Windows ==='
$and='MICH_LAN_ANDROID2PC_'+([guid]::NewGuid().ToString('N'))
Set-WinClip 'MICH_LAN_WIN_BASE'
Invoke-Phone $base POST '/clip' $and | Out-Null
$ok2=$false;$w=''
for($i=0;$i -lt 30;$i++){Start-Sleep -Milliseconds 500;$w=Get-WinClip;if($w -eq $and){$ok2=$true;break}}
Write-Host "ANDROID_TEXT_SENTINEL=$and`nWINDOWS_CLIP=$w`nLAN_ANDROID_TO_PC_OK=$ok2"
Write-Host '=== LAN Windows image to Android ==='
$pcImg=New-TestPngBytes 12 140 220
$pcImgHash=HashBytes $pcImg
Set-WinClipImage $pcImg
$ok3=$false;$imageStatus=$null
for($i=0;$i -lt 40;$i++){Start-Sleep -Milliseconds 500;try{$imageStatus=Status $base;if($imageStatus.imageHash -eq $pcImgHash){$ok3=$true;break}}catch{}}
Write-Host "PC_IMAGE_HASH=$pcImgHash`nANDROID_IMAGE_HASH=$($imageStatus.imageHash)`nLAN_PC_IMAGE_TO_ANDROID_OK=$ok3"
Write-Host '=== LAN Android image to Windows ==='
$andImg=New-TestPngBytes 220 80 40
$andImgHash=HashBytes $andImg
Set-WinClip 'MICH_LAN_WIN_IMAGE_BASE'
Post-Image $base $andImg
$ok4=$false;$winImgHash='';$winImgInfo=$null;$expectedRgb='220,80,40'
for($i=0;$i -lt 40;$i++){Start-Sleep -Milliseconds 500;$winImgInfo=Get-WinClipImageInfo;if($null -ne $winImgInfo){$winImgHash=$winImgInfo.Hash;if($winImgInfo.Width -eq 64 -and $winImgInfo.Height -eq 64 -and $winImgInfo.PixelRgb -eq $expectedRgb){$ok4=$true;break}}}
Write-Host "ANDROID_IMAGE_HASH=$andImgHash`nWINDOWS_IMAGE_HASH=$winImgHash`nWINDOWS_IMAGE_WIDTH=$($winImgInfo.Width)`nWINDOWS_IMAGE_HEIGHT=$($winImgInfo.Height)`nWINDOWS_IMAGE_TOP_LEFT_RGB=$($winImgInfo.PixelRgb)`nWINDOWS_IMAGE_EXPECTED_TOP_LEFT_RGB=$expectedRgb`nLAN_ANDROID_IMAGE_TO_WINDOWS_OK=$ok4"
if($accessOk -and $ok1 -and $ok2 -and $ok3 -and $ok4){exit 0}else{exit 1}
