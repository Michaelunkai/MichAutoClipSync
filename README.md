# MichAutoClipSync

MichAutoClipSync is a Windows tray app plus Android companion APK for LAN-first bidirectional clipboard synchronization between this Windows PC and Michael's Samsung S25 Ultra.

The live entry point is:

```text
F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync\MichAutoClipSyncTray.exe
```

## Current behavior

- Windows text copied to the clipboard is sent to Android over LAN.
- Android UI text copy events are sent back to Windows through the Samsung clipboard observer with an accessibility selected-text fallback.
- Windows image and screenshot clipboard payloads are sent to Android as pasteable image content.
- Android screenshots and screenshot-like MediaStore images are sent to the Windows clipboard as images.
- Runtime sync does not require Wireless Debugging, ADB forwarding, or USB; ADB is only used by install/build/verification scripts.
- The tray starts at Windows sign-in through StartupMaster, targeting the exact EXE above.

## Components

- `MichAutoClipSyncTray.exe`: native Windows tray application and user-facing launcher.
- `Start-MichAutoClipSync.ps1`: tray-owned sync runner. It discovers the Android bridge on LAN first and only attempts an ADB kick during startup recovery if LAN is unavailable.
- `com.mich.autoclipsync`: Android companion APK with a foreground LAN HTTP bridge, boot receiver, image provider, accessibility service, Samsung clipboard observer, and MediaStore image observer.
- `tools/AndroidClipboardProbe`: verification-only Android helper app used to simulate real UI text copy and screenshot-file image events.

## Android limitation

Android does not allow a normal sideloaded app to read every arbitrary private clipboard image URI from other apps while running in the background. This project therefore uses durable no-ADB paths that are available on this device:

- Samsung clipboard event plus accessibility selected-text fallback for Android UI text copy.
- MediaStore screenshot/screenshot-like image observer for Android screenshots and saved clipboard-like images.
- Companion bridge `/image` endpoint for explicit image payloads.

Direct background capture of every private image copied inside every Android app would require privileged/system/IME integration or an OEM-supported API.

## Build

Run from this folder in Windows PowerShell 5.1:

```powershell
.\build-tray.ps1
.\build-android.ps1
.\build-probe.ps1
```

Outputs:

- `MichAutoClipSyncTray.exe`
- `artifacts\build-output\MichAutoClipSync-debug.apk`
- `artifacts\build-output\AndroidClipboardProbe-debug.apk`

## Install and run

```powershell
.\install-MichAutoClipSync.ps1
```

The installer rebuilds the tray EXE and APK, installs the Android companion, enables the accessibility service, registers Windows startup, and launches the repo-local tray EXE.

The verified Windows startup task is:

```text
\MichStartupMaster\CustomStartup_MichAutoClipSyncTray_6ab3a629
```

## Verify

```powershell
.\verify-MichAutoClipSync.ps1
.\verify-AndroidBackgroundCopy.ps1
```

The verification suite checks:

1. Exact tray EXE is running.
2. Tray-owned sync runner is running.
3. Android bridge is reachable on LAN without an ADB forward.
4. Windows text clipboard reaches Android.
5. Android text copy reaches Windows.
6. Windows image/screenshot clipboard reaches Android.
7. Android screenshot-file image reaches Windows.
8. Android background observers are installed and reporting healthy status.

Latest committed proof files:

- `artifacts\proof\final-no-adb-lan-verify.txt`
- `artifacts\proof\android-background-copy-proof.txt`

## Important files

- `MichAutoClipSyncTray.cs`: Windows tray app source.
- `MichAutoClipSyncTray.exe`: exact runnable tray entry point.
- `Start-MichAutoClipSync.ps1`: LAN sync loop owned by the tray app.
- `install-MichAutoClipSync.ps1`: build/install/register/start script.
- `verify-MichAutoClipSync.ps1`: live LAN bidirectional verifier.
- `verify-AndroidBackgroundCopy.ps1`: Android background observer verifier.
- `app/src/main/java/com/mich/autoclipsync/`: Android companion source.
- `tools/AndroidClipboardProbe/`: verification helper source.
- `artifacts/proof/`: concise runtime proof files.

## Troubleshooting

- If the tray icon is missing after reboot, query `\MichStartupMaster\CustomStartup_MichAutoClipSyncTray_6ab3a629` and relaunch `MichAutoClipSyncTray.exe`.
- If LAN discovery fails, confirm the phone and PC are on the same network, then rerun `.\install-MichAutoClipSync.ps1` while ADB is available only for recovery/setup.
- If Android screenshots do not sync, confirm Android media image permissions are granted to `com.mich.autoclipsync`.
- If Android text copy does not sync, confirm the `MichAutoClipSync` accessibility service remains enabled.
