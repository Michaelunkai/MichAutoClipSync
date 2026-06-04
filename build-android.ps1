$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Sdk='C:\Users\micha\bubblewrap-tools\android_sdk'; $Bt=Join-Path $Sdk 'build-tools\34.0.0'; $JavaHome='C:\Users\micha\android-build-tools\jdk'
$env:JAVA_HOME=$JavaHome; $env:PATH="$JavaHome\bin;$Bt;$env:PATH"
$Out=Join-Path $Root 'artifacts\build-output\manual-build'; Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path $Out|Out-Null
$Aapt2=Join-Path $Bt 'aapt2.exe'; $AndroidJar=Join-Path $Sdk 'platforms\android-34\android.jar'; $Javac=Join-Path $JavaHome 'bin\javac.exe'; $D8=Join-Path $Bt 'd8.bat'; $ZipAlign=Join-Path $Bt 'zipalign.exe'; $ApkSigner=Join-Path $Bt 'apksigner.bat'; $Keytool=Join-Path $JavaHome 'bin\keytool.exe'
foreach($p in @($Aapt2,$AndroidJar,$Javac,$D8,$ZipAlign,$ApkSigner,$Keytool)){if(-not(Test-Path $p)){throw "Missing $p"}}
$resFlat=Join-Path $Out 'res.zip'; & $Aapt2 compile --dir (Join-Path $Root 'app\src\main\res') -o $resFlat; if($LASTEXITCODE -ne 0){throw 'aapt2 compile failed'}
$gen=Join-Path $Out 'gen'; New-Item -ItemType Directory -Force -Path $gen|Out-Null; $unsigned=Join-Path $Out 'base-unsigned.apk'
& $Aapt2 link -o $unsigned -I $AndroidJar --manifest (Join-Path $Root 'app\src\main\AndroidManifest.xml') --java $gen --min-sdk-version 23 --target-sdk-version 28 $resFlat; if($LASTEXITCODE -ne 0){throw 'aapt2 link failed'}
$classes=Join-Path $Out 'classes'; New-Item -ItemType Directory -Force -Path $classes|Out-Null; $srcs=@(); $srcs += Get-ChildItem -Recurse -Filter *.java (Join-Path $Root 'app\src\main\java') | % FullName; $srcs += Get-ChildItem -Recurse -Filter *.java $gen | % FullName
& $Javac -g:none -encoding UTF-8 -source 1.8 -target 1.8 -cp $AndroidJar -d $classes @srcs; if($LASTEXITCODE -ne 0){throw 'javac failed'}
$dex=Join-Path $Out 'dex'; New-Item -ItemType Directory -Force -Path $dex|Out-Null; $classFiles=Get-ChildItem -Recurse -Filter *.class $classes | % FullName
& $D8 --lib $AndroidJar --min-api 23 --output $dex @classFiles; if($LASTEXITCODE -ne 0){throw 'd8 failed'}
$apkWithDex=Join-Path $Out 'unsigned-dex.apk'; Copy-Item $unsigned $apkWithDex; Push-Location $dex; & jar uf $apkWithDex classes.dex; Pop-Location
$aligned=Join-Path $Out 'aligned.apk'; & $ZipAlign -f -p 4 $apkWithDex $aligned; if($LASTEXITCODE -ne 0){throw 'zipalign failed'}
$ks=Join-Path $Root 'artifacts\build-output\mich-debug.keystore'; if(-not(Test-Path $ks)){ & $Keytool -genkeypair -v -keystore $ks -storepass android -keypass android -alias michdebug -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=MichAutoClipSync,O=Hermes,C=US' | Out-Null }
$signed=Join-Path $Root 'artifacts\build-output\MichAutoClipSync-debug.apk'; & $ApkSigner sign --ks $ks --ks-pass pass:android --key-pass pass:android --ks-key-alias michdebug --out $signed $aligned; if($LASTEXITCODE -ne 0){throw 'apksigner failed'}
& $ApkSigner verify --verbose $signed
Get-Item $signed | Format-List FullName,Length,LastWriteTime
