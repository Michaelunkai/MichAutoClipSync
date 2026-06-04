$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$Src=Join-Path $Root 'MichAutoClipSyncTray.cs'
$Out=Join-Path $Root 'MichAutoClipSyncTray.exe'
& $Csc /nologo /target:winexe /platform:anycpu /optimize+ /out:$Out /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Management.dll $Src
if($LASTEXITCODE -ne 0){throw 'csc failed'}
Get-Item $Out | Format-List FullName,Length,LastWriteTime
