$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe'; $S='adb-R5CY610XJGV-vIqgVe._adb-tls-connect._tcp'
& $Adb -s $S shell screencap -p /sdcard/mich_verify_fail.png
& $Adb -s $S pull /sdcard/mich_verify_fail.png F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync\artifacts\proof\mich_verify_fail.png
& $Adb -s $S shell uiautomator dump /sdcard/mich_verify_fail.xml
& $Adb -s $S pull /sdcard/mich_verify_fail.xml F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync\artifacts\proof\mich_verify_fail.xml
