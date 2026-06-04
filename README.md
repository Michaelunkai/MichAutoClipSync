# MichAutoClipSync

MichAutoClipSync is a Windows system-tray + Android companion project for bidirectional clipboard synchronization experiments on Michael's Samsung S25 Ultra.

It creates:

- `MichAutoClipSyncTray.exe`: a native Windows tray application with a green project-related `M` tray icon.
- `Start-MichAutoClipSync.ps1`: the tray-owned sync runner that keeps ADB forwarding and clipboard polling alive.
- `com.mich.autoclipsync`: an Android companion APK with a foreground service, local HTTP bridge, and accessibility clipboard observer.
- `MichAutoClipSync Tray`: a Windows logon scheduled task so the tray app starts after Windows sign-in.

## Important Android limitation

Windows to Android works through the tray runner and ADB bridge. Android companion-app copy to Windows is supported and testable. Arbitrary copy events from every third-party Android app (Telegram, Chrome, WhatsApp, etc.) are restricted by Android/Samsung security for normal sideloaded apps. This repo records the exact blocker observed during the original mission: Samsung Android 16 returned `No shell command implementation` for `cmd clipboard get`, and arbitrary other-app copy events were not exposed to the sideloaded app even with foreground service, accessibility service, and clipboard appops allowed.

For true every-app Android to Windows clipboard sync, the privileged route is official Microsoft Phone Link / Samsung Link to Windows after its connection-delay state is fixed, or a privileged/system/IME-style integration explicitly approved by the user.

## Prerequisites

- Windows PowerShell 5.1.
- Existing `aadb` function in the user's PowerShell profile.
- Android platform tools at `C:\Users\micha\AppData\Local\Android\platform-tools\adb.exe`.
- Android SDK/build tools at `C:\Users\micha\bubblewrap-tools\android_sdk`.
- JDK at `C:\Users\micha\android-build-tools\jdk`.
- Authorized ADB device: Samsung S25 Ultra `SM-S938B`.

## Build

From this folder in Windows PowerShell 5.1:

```powershell
.\build-tray.ps1
.\build-android.ps1
```

Outputs:

- `MichAutoClipSyncTray.exe`
- `artifacts\build-output\MichAutoClipSync-debug.apk`

## Install and run

```powershell
.\install-MichAutoClipSync.ps1
```

This installs the APK, starts the Android service, enables the companion accessibility service, registers the Windows logon scheduled task, and launches the repo-local tray EXE.

## Verify

```powershell
.\verify-MichAutoClipSync.ps1
```

The verifier checks:

1. Tray EXE is running.
2. Tray-owned runner is running.
3. Android accessibility service is enabled.
4. Windows clipboard reaches Android bridge.
5. Android companion app copy reaches Windows clipboard.

## Important files

- `MichAutoClipSyncTray.cs` — native Windows tray app source.
- `MichAutoClipSyncTray.exe` — runnable tray app entry point.
- `Start-MichAutoClipSync.ps1` — sync loop owned by the tray app.
- `install-MichAutoClipSync.ps1` — build/install/register/start script.
- `verify-MichAutoClipSync.ps1` — live bidirectional proof script.
- `app/src/main/java/com/mich/autoclipsync/` — Android companion source.
- `artifacts/mission-notes/` — copied notes from the Telegram mission.
- `artifacts/proof/` — verification and runtime logs.

## Troubleshooting

- If the tray icon is missing after reboot, run `schtasks /Query /TN "MichAutoClipSync Tray" /V /FO LIST` and then run `MichAutoClipSyncTray.exe` manually.
- If Android is not connected, run `aadb connect` and `aadb devices -l`.
- If Windows to Android works but Android arbitrary app copy does not, inspect Phone Link / Link to Windows. The observed blocker was a Link to Windows connection-delay screen.
- If `cmd clipboard get` says `No shell command implementation`, use the companion app verification path or fix Phone Link; shell clipboard is unavailable on this Samsung build.
