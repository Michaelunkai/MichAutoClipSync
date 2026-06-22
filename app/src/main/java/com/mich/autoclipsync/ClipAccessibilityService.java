package com.mich.autoclipsync;

import android.accessibilityservice.AccessibilityService;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.List;

public class ClipAccessibilityService extends AccessibilityService {
    ClipboardManager clipboard;
    volatile boolean running;
    String lastText = "";
    String lastImageHash = "";
    static volatile String lastSelection = "";
    static volatile long lastSelectionSeen = 0;

    public void onServiceConnected() {
        clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        running = true;
        startBridge("accessibility_connected");
        try {
            clipboard.addPrimaryClipChangedListener(new ClipboardManager.OnPrimaryClipChangedListener() {
                public void onPrimaryClipChanged() {
                    observe("accessibility_listener");
                }
            });
        } catch (Throwable t) {
            ClipBridgeService.publishAccessibilityState("accessibility_listener_error", t.getClass().getSimpleName());
        }
        Thread poller = new Thread(new Runnable() {
            public void run() {
                while (running) {
                    observe("accessibility_poll");
                    try {
                        Thread.sleep(250);
                    } catch (InterruptedException ignored) {
                    }
                }
            }
        }, "MichAutoClipSyncAccessibilityPoll");
        poller.setDaemon(true);
        poller.start();
        observe("accessibility_connected");
    }

    public void onAccessibilityEvent(AccessibilityEvent event) {
        captureSelection(event);
        observe("accessibility_event");
    }

    public void onInterrupt() {
        ClipBridgeService.publishAccessibilityState("accessibility_interrupt", "");
    }

    public void onDestroy() {
        running = false;
        ClipBridgeService.publishAccessibilityStopped("accessibility_destroyed");
        super.onDestroy();
    }

    void startBridge(String reason) {
        try {
            if (ClipBridgeService.instance == null) {
                Intent service = new Intent(this, ClipBridgeService.class);
                service.putExtra("source", reason);
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
            }
            ClipBridgeService.publishAccessibilityState(reason, "");
        } catch (Throwable t) {
            ClipBridgeService.publishAccessibilityState(reason + "_bridge_start_error", t.getClass().getSimpleName());
        }
    }

    void observe(String source) {
        startBridge(source);
        try {
            if (clipboard == null) clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard == null || !clipboard.hasPrimaryClip()) {
                ClipBridgeService.publishAccessibilityState(source + "_empty", "");
                return;
            }
            ClipData clip = clipboard.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) {
                ClipBridgeService.publishAccessibilityState(source + "_empty_clip", "");
                return;
            }
            ClipData.Item item = clip.getItemAt(0);
            Uri uri = item.getUri();
            if (uri != null) {
                try {
                    byte[] image = ClipBridgeService.readAll(getContentResolver().openInputStream(uri));
                    if (image.length > 0) {
                        String hash = ClipBridgeService.sha(image);
                        if (!hash.equals(lastImageHash)) {
                            lastImageHash = hash;
                            lastText = "";
                            ClipBridgeService.publishObservedImage(image, source);
                        }
                        ClipBridgeService.publishAccessibilityState(source, "");
                        return;
                    }
                } catch (Throwable ignored) {
                    // Some clipboard URIs are text/document providers; fall back to coerceToText.
                }
            }
            CharSequence chars = item.coerceToText(this);
            String text = chars == null ? "" : chars.toString();
            if (!text.equals(lastText)) {
                lastText = text;
                lastImageHash = "";
                ClipBridgeService.publishObservedText(text, source);
            }
            ClipBridgeService.publishAccessibilityState(source, "");
        } catch (Throwable t) {
            ClipBridgeService.publishAccessibilityState(source + "_blocked", t.getClass().getSimpleName());
        }
    }

    void captureSelection(AccessibilityEvent event) {
        if (event == null) return;
        String text = eventText(event);
        String selected = selectedText(event, text);
        if (selected.length() > 0) {
            lastSelection = selected;
            lastSelectionSeen = System.currentTimeMillis();
        }
        ClipBridgeService.publishAccessibilityEventDebug(event.getEventType() + ":" + text, selected);
    }

    String eventText(AccessibilityEvent event) {
        StringBuilder sb = new StringBuilder();
        try {
            List<CharSequence> list = event.getText();
            if (list != null) {
                for (CharSequence c : list) {
                    if (c == null) continue;
                    if (sb.length() > 0) sb.append("\n");
                    sb.append(c);
                }
            }
        } catch (Throwable ignored) {
        }
        return sb.toString();
    }

    String selectedText(AccessibilityEvent event, String fallbackText) {
        try {
            AccessibilityNodeInfo node = event.getSource();
            if (node != null) {
                try {
                    CharSequence nodeText = node.getText();
                    int start = node.getTextSelectionStart();
                    int end = node.getTextSelectionEnd();
                    if (nodeText != null && start >= 0 && end > start && end <= nodeText.length()) {
                        return nodeText.subSequence(start, end).toString();
                    }
                } finally {
                    try { node.recycle(); } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable ignored) {
        }
        try {
            int start = event.getFromIndex();
            int end = event.getToIndex();
            if (fallbackText != null && start >= 0 && end > start && end <= fallbackText.length()) {
                return fallbackText.substring(start, end);
            }
        } catch (Throwable ignored) {
        }
        return "";
    }

    static boolean publishLastKnownSelection(String source) {
        String text = lastSelection;
        long age = System.currentTimeMillis() - lastSelectionSeen;
        if (text != null && text.length() > 0 && age >= 0 && age < 60000) {
            ClipBridgeService.publishObservedText(text, source);
            ClipBridgeService.publishAccessibilityState(source, "");
            return true;
        }
        ClipBridgeService.publishAccessibilityState(source + "_no_recent_selection", "");
        return false;
    }
}
