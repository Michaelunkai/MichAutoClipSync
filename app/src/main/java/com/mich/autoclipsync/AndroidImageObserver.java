package com.mich.autoclipsync;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.database.ContentObserver;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.MediaStore;
import java.io.InputStream;

class AndroidImageObserver {
    final Context context;
    final long startedAtSeconds;
    long lastSeenId = -1;
    HandlerThread thread;
    volatile boolean running;

    AndroidImageObserver(Context context) {
        this.context = context.getApplicationContext();
        this.startedAtSeconds = System.currentTimeMillis() / 1000L;
    }

    void start() {
        try {
            scanLatest("media_image_initial", false);
            thread = new HandlerThread("MichAutoClipSyncImageObserver");
            thread.start();
            Handler handler = new Handler(thread.getLooper());
            context.getContentResolver().registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, new ContentObserver(handler) {
                public void onChange(boolean selfChange) {
                    onChange(selfChange, null);
                }

                public void onChange(boolean selfChange, Uri uri) {
                    try {
                        Thread.sleep(450);
                    } catch (InterruptedException ignored) {
                    }
                    scanLatest("media_image_observer", true);
                }
            });
            running = true;
            ClipBridgeService.publishMediaImageState(true, "media_image_registered", "", "");
        } catch (Throwable t) {
            ClipBridgeService.publishMediaImageState(false, "media_image_register_blocked", rootName(t), "");
        }
    }

    void scanLatest(String source, boolean publish) {
        Cursor cursor = null;
        try {
            ContentResolver resolver = context.getContentResolver();
            String[] projection = new String[] {
                    MediaStore.Images.Media._ID,
                    MediaStore.Images.Media.DISPLAY_NAME,
                    MediaStore.Images.Media.DATE_ADDED,
                    MediaStore.Images.Media.MIME_TYPE,
                    MediaStore.Images.Media.RELATIVE_PATH
            };
            cursor = resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, null, null, MediaStore.Images.Media.DATE_ADDED + " DESC");
            if (cursor == null) {
                ClipBridgeService.publishMediaImageState(running, source + "_null_cursor", "", "");
                return;
            }
            int idColumn = cursor.getColumnIndex(MediaStore.Images.Media._ID);
            int nameColumn = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME);
            int dateColumn = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED);
            int mimeColumn = cursor.getColumnIndex(MediaStore.Images.Media.MIME_TYPE);
            int pathColumn = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH);
            int checked = 0;
            while (cursor.moveToNext() && checked < 40) {
                checked++;
                long id = cursor.getLong(idColumn);
                String name = value(cursor, nameColumn);
                String path = value(cursor, pathColumn);
                String mime = value(cursor, mimeColumn);
                long date = cursor.getLong(dateColumn);
                if (!isRelevantImage(name, path, mime)) continue;
                if (!publish) {
                    lastSeenId = id;
                    ClipBridgeService.publishMediaImageState(true, source, "", displayName(path, name));
                    return;
                }
                if (id == lastSeenId) {
                    ClipBridgeService.publishMediaImageState(true, source + "_unchanged", "", displayName(path, name));
                    return;
                }
                if (date + 10 < startedAtSeconds) {
                    lastSeenId = id;
                    ClipBridgeService.publishMediaImageState(true, source + "_old_ignored", "", displayName(path, name));
                    return;
                }
                Uri uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id);
                InputStream in = resolver.openInputStream(uri);
                byte[] bytes = ClipBridgeService.readAll(in);
                if (bytes.length > 0) {
                    lastSeenId = id;
                    ClipBridgeService.publishObservedImage(bytes, source);
                    ClipBridgeService.publishMediaImageState(true, source, "", displayName(path, name));
                    return;
                }
            }
            ClipBridgeService.publishMediaImageState(true, source + "_none", "", "");
        } catch (Throwable t) {
            ClipBridgeService.publishMediaImageState(running, source + "_blocked", rootName(t), "");
        } finally {
            try { if (cursor != null) cursor.close(); } catch (Throwable ignored) {}
        }
    }

    boolean isRelevantImage(String name, String path, String mime) {
        String s = ((name == null ? "" : name) + " " + (path == null ? "" : path)).toLowerCase();
        boolean image = mime == null || mime.length() == 0 || mime.toLowerCase().startsWith("image/");
        return image && (s.indexOf("screenshot") >= 0 || s.indexOf("screen_shot") >= 0 || s.indexOf("screenshots") >= 0 || s.indexOf("clipboard") >= 0 || s.indexOf("clip") >= 0);
    }

    String value(Cursor cursor, int column) {
        if (column < 0) return "";
        try {
            String value = cursor.getString(column);
            return value == null ? "" : value;
        } catch (Throwable ignored) {
            return "";
        }
    }

    String displayName(String path, String name) {
        return (path == null ? "" : path) + (name == null ? "" : name);
    }

    String rootName(Throwable t) {
        Throwable x = t;
        while (x != null && x.getCause() != null) x = x.getCause();
        return x == null ? "" : x.getClass().getSimpleName();
    }
}
