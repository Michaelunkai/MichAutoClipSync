# Mission notes

This project packages the Telegram `/aadb` and `/study` mission that created a clipboard sync tray app.

## What was proven during the mission

- A native tray EXE can own a PowerShell 5.1 runner and keep the ADB clipboard bridge alive.
- Windows to Android clipboard transfer works through the local bridge.
- Android companion-app clipboard events can be observed and mirrored to Windows.
- Android/Samsung arbitrary third-party app clipboard capture remains blocked for a normal sideloaded app.
- Official Link to Windows showed a connection-delay state and must be fully connected for its privileged arbitrary-app clipboard path.

## Copied-not-moved production exception

The live production attempt originally ran under `C:\Temp\hermes_aadb\HermesClipboardSync`. That location was treated as live/temporary production and is not relied on by this repository. The final project recreates the app under `F:\study` as `MichAutoClipSync` with repo-local scripts and a repo-local tray EXE.

## Required acceptance standard

Do not claim every Android app copies to Windows unless a live Telegram/Chrome/other-app copy sentinel passes through a privileged path such as fully connected Phone Link / Link to Windows, or a user-approved privileged/IME/system integration.
