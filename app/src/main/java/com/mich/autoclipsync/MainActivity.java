package com.mich.autoclipsync;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Typeface;
import android.provider.Settings;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    EditText edit;
    TextView status;

    protected void onCreate(Bundle bundle) {
        super.onCreate(bundle);
        startSvc();
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("MichAutoClipSync");
        title.setTextSize(22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        status = new TextView(this);
        root.addView(status);

        edit = new EditText(this);
        edit.setTextSize(18);
        edit.setSingleLine(false);
        edit.setMinLines(3);
        edit.setMaxLines(6);
        edit.setHint("Type/paste text here, then tap Copy field.");
        root.addView(edit, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        Button copy = new Button(this);
        copy.setText("Copy field");
        copy.setOnClickListener(v -> copyField());
        Button paste = new Button(this);
        paste.setText("Paste clipboard");
        paste.setOnClickListener(v -> pasteField());
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
        row.addView(paste, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(row);

        Button accessibility = new Button(this);
        accessibility.setText("Open Accessibility Settings");
        accessibility.setOnClickListener(v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));
        root.addView(accessibility, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
        applyIntent(getIntent());
        updateStatus();
    }

    protected void onResume() {
        super.onResume();
        startSvc();
        updateStatus();
    }

    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        applyIntent(intent);
    }

    void applyIntent(Intent intent) {
        if (intent == null || edit == null) return;
        if (intent.hasExtra("seed_text")) edit.setText(intent.getStringExtra("seed_text"));
        if (intent.hasExtra("copy_text")) {
            edit.setText(intent.getStringExtra("copy_text"));
            copyField();
        }
    }

    void startSvc() {
        Intent service = new Intent(this, ClipBridgeService.class);
        service.putExtra("source", "activity");
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
    }

    void copyField() {
        String text = edit.getText().toString();
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("MichAutoClipSync", text));
        ClipBridgeService.publishObservedText(text, "activity_copy");
        updateStatus("Copied " + text.length() + " chars to Android clipboard.");
    }

    void pasteField() {
        try {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard.hasPrimaryClip() && clipboard.getPrimaryClip() != null && clipboard.getPrimaryClip().getItemCount() > 0) {
                CharSequence chars = clipboard.getPrimaryClip().getItemAt(0).coerceToText(this);
                edit.setText(chars == null ? "" : chars.toString());
            }
            updateStatus();
        } catch (Throwable t) {
            updateStatus("Paste failed: " + t.getClass().getSimpleName());
        }
    }

    void updateStatus() {
        updateStatus("");
    }

    void updateStatus(String prefix) {
        boolean enabled = isAccessibilityEnabled();
        String message = (prefix == null || prefix.length() == 0 ? "" : prefix + "\n")
                + "LAN bridge active. Android-to-Windows automatic background sync requires MichAutoClipSync accessibility: "
                + (enabled ? "ENABLED" : "DISABLED");
        status.setText(message);
    }

    boolean isAccessibilityEnabled() {
        try {
            String enabled = Settings.Secure.getString(getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            if (enabled == null) return false;
            String needle = "com.mich.autoclipsync/com.mich.autoclipsync.ClipAccessibilityService";
            return enabled.toLowerCase().contains(needle.toLowerCase());
        } catch (Throwable t) {
            return false;
        }
    }
}
