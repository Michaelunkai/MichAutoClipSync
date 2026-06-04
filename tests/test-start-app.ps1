$Adb='C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe';$S='adb-R5CY610XJGV-vIqgVe._adb-tls-connect._tcp'
& $Adb -s $S shell am start -S -n com.mich.autoclipsync/.MainActivity --es seed_text TESTSEED
Start-Sleep -Seconds 1
& $Adb -s $S shell dumpsys window | Select-String -Pattern 'mCurrentFocus|mFocusedApp'
