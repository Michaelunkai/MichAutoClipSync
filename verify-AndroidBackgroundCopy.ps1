$ErrorActionPreference='Continue'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'
$ProbeApk=Join-Path $Root 'artifacts\build-output\AndroidClipboardProbe-debug.apk'
$Proof=Join-Path $Root 'artifacts\proof\android-background-copy-proof.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $Proof -Parent) | Out-Null
Remove-Item -Force -Path $Proof -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

function Write-Proof([string]$Line) {
  Write-Host $Line
  Add-Content -Path $Proof -Value $Line -Encoding UTF8
}

function Get-Serial {
  $lines=& $Adb devices -l
  $serial=(($lines | Where-Object { $_ -match '\sdevice\s' -and $_ -notmatch '\(2\)' -and $_ -notmatch '^192\.168\.' } | Select-Object -First 1) -split '\s+')[0]
  if(-not $serial){ $serial=(($lines | Where-Object { $_ -match '\sdevice\s' -and $_ -notmatch '^192\.168\.' } | Select-Object -First 1) -split '\s+')[0] }
  return $serial
}

function Invoke-Phone([string]$Base,[string]$Path) {
  $req=[Net.HttpWebRequest]::Create("$Base$Path")
  $req.Proxy=$null
  $req.Timeout=3000
  $req.ReadWriteTimeout=3000
  $res=$req.GetResponse()
  try {
    $sr=New-Object IO.StreamReader($res.GetResponseStream(),[Text.Encoding]::UTF8)
    $txt=$sr.ReadToEnd()
    $sr.Close()
    return $txt
  } finally {
    $res.Close()
  }
}

function Status([string]$Base) {
  (Invoke-Phone $Base '/status') | ConvertFrom-Json
}

function Convert-StatusForProof($Status,[string]$ExpectedSelection='') {
  if($null -eq $Status){ return '' }
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
    lastAccessibilitySelectionMatchesExpected=((-not [string]::IsNullOrEmpty($ExpectedSelection)) -and $selection -eq $ExpectedSelection)
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

function Get-WinClip {
  try { [System.Windows.Forms.Clipboard]::GetText() } catch { '' }
}

function Set-WinClip([string]$Text) {
  try { [System.Windows.Forms.Clipboard]::SetText($Text) } catch {}
}

function Get-WinClipImageBytes {
  try {
    if(-not [System.Windows.Forms.Clipboard]::ContainsImage()){ return $null }
    $img=[System.Windows.Forms.Clipboard]::GetImage()
    $ms=New-Object IO.MemoryStream
    $img.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png)
    return $ms.ToArray()
  } catch {
    return $null
  }
}

function HashBytes([byte[]]$Bytes) {
  if($null -eq $Bytes -or $Bytes.Length -eq 0){ return '' }
  $sha=[Security.Cryptography.SHA256]::Create()
  (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-WinClipImageInfo {
  try {
    if(-not [System.Windows.Forms.Clipboard]::ContainsImage()){ return $null }
    $img=[System.Windows.Forms.Clipboard]::GetImage()
    if($null -eq $img){ return $null }
    $bmp=New-Object System.Drawing.Bitmap($img)
    try {
      $px=$bmp.GetPixel(0,0)
      $bytes=Get-WinClipImageBytes
      [pscustomobject]@{
        Width=$bmp.Width
        Height=$bmp.Height
        PixelRgb="$($px.R),$($px.G),$($px.B)"
        Hash=HashBytes $bytes
      }
    } finally {
      $bmp.Dispose()
      $img.Dispose()
    }
  } catch {
    return $null
  }
}

function Get-Base {
  $baseFile=Join-Path $Root 'artifacts\proof\phone-base-url.txt'
  $candidates=@()
  if(Test-Path $baseFile){ $candidates += (Get-Content -Path $baseFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim() }
  $candidates += 'http://192.168.1.124:8765'
  foreach($base in $candidates | Where-Object { $_ } | Select-Object -Unique){
    try {
      $st=Status $base
      if($st.ok){ return $base }
    } catch {}
  }
  return $null
}

Remove-Item -LiteralPath $Proof -Force -ErrorAction SilentlyContinue
Write-Proof '=== Android background copy proof ==='
$serial=Get-Serial
Write-Proof "SERIAL=$serial"
if(-not $serial){ Write-Proof 'NO_AUTHORIZED_ANDROID_DEVICE'; exit 2 }
if(-not(Test-Path $ProbeApk)){ Write-Proof "MISSING_PROBE_APK=$ProbeApk"; exit 2 }

Write-Proof '=== install verifier probe ==='
& $Adb -s $serial shell settings put global verifier_verify_adb_installs 0 | Out-Null
(& $Adb -s $serial install -r -t -g --no-streaming $ProbeApk 2>&1) | ForEach-Object { Write-Proof $_ }

$svc='com.mich.autoclipsync/com.mich.autoclipsync.ClipAccessibilityService'
$enabledRaw=(& $Adb -s $serial shell settings --user 0 get secure enabled_accessibility_services 2>$null | Out-String).Trim()
if([string]::IsNullOrWhiteSpace($enabledRaw) -or $enabledRaw -eq 'null'){
  $enabledNew=$svc
} elseif(($enabledRaw -split ':') -contains $svc){
  $enabledNew=$enabledRaw
} else {
  $enabledNew="$enabledRaw`:$svc"
}
& $Adb -s $serial shell settings --user 0 put secure enabled_accessibility_services $enabledNew | Out-Null
& $Adb -s $serial shell settings --user 0 put secure accessibility_enabled 1 | Out-Null
& $Adb -s $serial shell am start-foreground-service -n com.mich.autoclipsync/.ClipBridgeService | Out-Null
Start-Sleep -Seconds 2

$base=Get-Base
Write-Proof "LAN_BASE=$base"
if(-not $base){ Write-Proof 'LAN_BASE_OK=False'; exit 2 }
$initial=Status $base
Write-Proof "INITIAL_STATUS=$(Convert-StatusForProof $initial)"
$accessOk=($initial.accessibilityRunning -eq $true -and [int64]$initial.accessibilityAgeMs -lt 5000 -and [string]::IsNullOrEmpty([string]$initial.lastAccessibilityError) -and $initial.mediaImageObserverRunning -eq $true)
Write-Proof "ANDROID_BACKGROUND_OBSERVER_OK=$accessOk"
if(-not $accessOk){ exit 1 }

Write-Proof '=== background text copy from separate Android app ==='
Set-WinClip 'MICH_BACKGROUND_TEXT_BASE'
& $Adb -s $serial shell input keyevent HOME | Out-Null
Start-Sleep -Seconds 1
$text='MICH_ANDROID_BACKGROUND_TEXT_'+([guid]::NewGuid().ToString('N'))
& $Adb -s $serial shell am start -n com.mich.clipprobe/.ProbeActivity --es mode uitext --es text $text | Out-Null
$textOk=$false
$winText=''
$textStatus=$null
for($i=0;$i -lt 50;$i++){
  Start-Sleep -Milliseconds 500
  try { $textStatus=Status $base } catch {}
  $winText=Get-WinClip
  if($winText -eq $text -and ([string]$textStatus.lastSource -like '*accessibility*' -or [string]$textStatus.lastAccessibilitySelection -eq $text)){ $textOk=$true; break }
}
$focus=(& $Adb -s $serial shell dumpsys window | Select-String -Pattern 'mCurrentFocus|mFocusedApp' | Out-String).Trim()
Write-Proof "ANDROID_TEXT_SENTINEL=$text"
Write-Proof "WINDOWS_CLIP=$winText"
Write-Proof "TEXT_STATUS=$(Convert-StatusForProof $textStatus $text)"
Write-Proof "ANDROID_FOCUS_AFTER_TEXT=$focus"
Write-Proof "ANDROID_BACKGROUND_TEXT_TO_WINDOWS_OK=$textOk"

Write-Proof '=== background screenshot image from separate Android app ==='
Set-WinClip 'MICH_BACKGROUND_IMAGE_BASE'
Start-Sleep -Seconds 1
& $Adb -s $serial shell input keyevent HOME | Out-Null
Start-Sleep -Seconds 1
$red=Get-Random -Minimum 32 -Maximum 224
$green=Get-Random -Minimum 32 -Maximum 224
$blue=Get-Random -Minimum 32 -Maximum 224
$expectedRgb="$red,$green,$blue"
& $Adb -s $serial shell am start -n com.mich.clipprobe/.ProbeActivity --es mode screenshotfile --ei red $red --ei green $green --ei blue $blue | Out-Null
$imageOk=$false
$imageStatus=$null
$winImageHash=''
$winImageInfo=$null
for($i=0;$i -lt 60;$i++){
  Start-Sleep -Milliseconds 500
  try { $imageStatus=Status $base } catch {}
  $winImageInfo=Get-WinClipImageInfo
  if($null -ne $winImageInfo){ $winImageHash=$winImageInfo.Hash }
  $observerOk=([string]$imageStatus.lastSource -like 'media_image*' -or [string]$imageStatus.lastMediaImageSource -like 'media_image_observer*')
  $windowsImageMatches=($null -ne $winImageInfo -and $winImageInfo.Width -eq 128 -and $winImageInfo.Height -eq 96 -and $winImageInfo.PixelRgb -eq $expectedRgb)
  if($imageStatus.kind -eq 'image' -and $imageStatus.imageHash -and $observerOk -and $windowsImageMatches){
    $imageOk=$true
    break
  }
}
$focus=(& $Adb -s $serial shell dumpsys window | Select-String -Pattern 'mCurrentFocus|mFocusedApp' | Out-String).Trim()
Write-Proof "ANDROID_IMAGE_HASH=$($imageStatus.imageHash)"
Write-Proof "WINDOWS_IMAGE_HASH=$winImageHash"
Write-Proof "WINDOWS_IMAGE_WIDTH=$($winImageInfo.Width)"
Write-Proof "WINDOWS_IMAGE_HEIGHT=$($winImageInfo.Height)"
Write-Proof "WINDOWS_IMAGE_TOP_LEFT_RGB=$($winImageInfo.PixelRgb)"
Write-Proof "WINDOWS_IMAGE_EXPECTED_TOP_LEFT_RGB=$expectedRgb"
Write-Proof "IMAGE_STATUS=$(Convert-StatusForProof $imageStatus)"
Write-Proof "ANDROID_FOCUS_AFTER_IMAGE=$focus"
Write-Proof "ANDROID_BACKGROUND_IMAGE_TO_WINDOWS_OK=$imageOk"

Write-Proof '=== cleanup verifier probe ==='
& $Adb -s $serial shell am force-stop com.mich.clipprobe | Out-Null
(& $Adb -s $serial uninstall com.mich.clipprobe 2>&1) | ForEach-Object { Write-Proof $_ }

if($textOk -and $imageOk){ exit 0 }
exit 1
