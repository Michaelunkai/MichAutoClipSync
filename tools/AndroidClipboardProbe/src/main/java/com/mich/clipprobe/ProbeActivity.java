package com.mich.clipprobe;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.util.Log;
import android.R;
import android.provider.MediaStore;
import android.widget.EditText;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

public class ProbeActivity extends Activity {
    protected void onCreate(Bundle bundle) {
        super.onCreate(bundle);
        TextView textView = new TextView(this);
        textView.setText("MichClipboardProbe copying...");
        textView.setTextSize(22);
        setContentView(textView);
        String mode = getIntent() == null ? "text" : getIntent().getStringExtra("mode");
        try {
            if ("uitext".equals(mode)) {
                copyUiText();
                return;
            } else if ("screenshotfile".equals(mode)) {
                saveScreenshotFile();
            } else if ("image".equals(mode)) copyImage();
            else copyText();
            Log.i("MichClipboardProbe", "copy ok mode=" + mode);
        } catch (Throwable ignored) {
            Log.e("MichClipboardProbe", "copy failed mode=" + mode, ignored);
        }
        new Handler().postDelayed(new Runnable() {
            public void run() {
                Intent home = new Intent(Intent.ACTION_MAIN);
                home.addCategory(Intent.CATEGORY_HOME);
                home.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(home);
                finishAndRemoveTask();
            }
        }, 1500);
    }

    void copyUiText() {
        final EditText editText = new EditText(this);
        String text = getIntent().getStringExtra("text");
        if (text == null) text = "";
        editText.setText(text);
        editText.setTextSize(20);
        editText.setSelectAllOnFocus(true);
        setContentView(editText);
        editText.requestFocus();
        editText.selectAll();
        new Handler().postDelayed(new Runnable() {
            public void run() {
                try {
                    editText.selectAll();
                    editText.onTextContextMenuItem(R.id.copy);
                    Log.i("MichClipboardProbe", "ui copy ok");
                } catch (Throwable t) {
                    Log.e("MichClipboardProbe", "ui copy failed", t);
                }
                Intent home = new Intent(Intent.ACTION_MAIN);
                home.addCategory(Intent.CATEGORY_HOME);
                home.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(home);
                finishAndRemoveTask();
            }
        }, 900);
    }

    void copyText() {
        String text = getIntent().getStringExtra("text");
        if (text == null) text = "";
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("MichClipboardProbe", text));
    }

    void copyImage() throws Exception {
        int red = getIntent().getIntExtra("red", 32);
        int green = getIntent().getIntExtra("green", 160);
        int blue = getIntent().getIntExtra("blue", 220);
        File image = ProbeImageProvider.imageFile(this);
        FileOutputStream out = new FileOutputStream(image);
        Bitmap bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.rgb(red, green, blue));
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.WHITE);
        canvas.drawCircle(48, 48, 32, paint);
        paint.setColor(Color.BLACK);
        paint.setTextSize(20);
        canvas.drawText("M", 40, 55, paint);
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
        out.close();
        bitmap.recycle();
        Uri uri = Uri.parse("content://com.mich.clipprobe.imageprovider/probe/probe_clip.png");
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newUri(getContentResolver(), "MichClipboardProbe image", uri));
    }

    void saveScreenshotFile() throws Exception {
        int red = getIntent().getIntExtra("red", 45);
        int green = getIntent().getIntExtra("green", 190);
        int blue = getIntent().getIntExtra("blue", 95);
        Bitmap bitmap = Bitmap.createBitmap(128, 96, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.rgb(red, green, blue));
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.WHITE);
        paint.setTextSize(18);
        canvas.drawText("SCREEN", 18, 50, paint);
        String name = "Screenshot_MichProbe_" + System.currentTimeMillis() + ".png";
        ContentValues values = new ContentValues();
        values.put(MediaStore.Images.Media.DISPLAY_NAME, name);
        values.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
        if (Build.VERSION.SDK_INT >= 29) {
            values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Screenshots");
            values.put(MediaStore.Images.Media.IS_PENDING, 1);
        }
        Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
        if (uri == null) throw new IllegalStateException("insert returned null");
        OutputStream out = getContentResolver().openOutputStream(uri);
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
        out.close();
        bitmap.recycle();
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues done = new ContentValues();
            done.put(MediaStore.Images.Media.IS_PENDING, 0);
            getContentResolver().update(uri, done, null, null);
        }
    }
}
