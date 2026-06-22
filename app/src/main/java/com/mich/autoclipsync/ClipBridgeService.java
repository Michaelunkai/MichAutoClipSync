package com.mich.autoclipsync;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.os.Build;
import android.os.IBinder;
import android.content.Intent;
import android.content.Context;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.net.Uri;
import android.util.Base64;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

public class ClipBridgeService extends Service {
    static volatile String lastText = "";
    static volatile byte[] lastImage = new byte[0];
    static volatile String lastImageHash = "";
    static volatile long lastChange = 0;
    static volatile String lastSource = "boot";
    static volatile String lastKind = "text";
    static volatile long serviceStarted = 0;
    static volatile long lastClipboardRead = 0;
    static volatile String lastClipboardReadError = "";
    static volatile boolean accessibilityRunning = false;
    static volatile long lastAccessibilitySeen = 0;
    static volatile String lastAccessibilitySource = "never";
    static volatile String lastAccessibilityError = "";
    static volatile String lastAccessibilityEvent = "";
    static volatile String lastAccessibilitySelection = "";
    static volatile long lastAccessibilitySelectionSeen = 0;
    static volatile boolean semClipboardAvailable = false;
    static volatile boolean semClipboardRunning = false;
    static volatile long lastSemClipboardSeen = 0;
    static volatile String lastSemClipboardSource = "never";
    static volatile String lastSemClipboardError = "";
    static volatile String semClipboardClass = "";
    static volatile int semClipboardClipCount = -1;
    static volatile String semClipboardClipClasses = "";
    static volatile long semClipboardEventCount = 0;
    static volatile String lastSemClipboardEvent = "";
    static volatile String lastSemClipboardEventArgs = "";
    static volatile long lastSemClipboardPublish = 0;
    static volatile String semClipboardMethods = "";
    static volatile boolean mediaImageObserverRunning = false;
    static volatile long lastMediaImageSeen = 0;
    static volatile String lastMediaImageSource = "never";
    static volatile String lastMediaImageError = "";
    static volatile String lastMediaImageName = "";
    static ClipBridgeService instance;
    ClipboardManager cm;
    ServerSocket server;
    SamsungClipboardObserver samsungClipboardObserver;
    AndroidImageObserver androidImageObserver;
    boolean running = true;

    public IBinder onBind(Intent i) { return null; }
    public void onCreate() { super.onCreate(); instance=this; serviceStarted=System.currentTimeMillis(); cm=(ClipboardManager)getSystemService(CLIPBOARD_SERVICE); startFg(); startSamsungClipboardObserver(); startAndroidImageObserver(); listen(); startPoll(); startBeacon(); startHttp(); }
    public int onStartCommand(Intent i, int flags, int id) { running=true; if(i!=null && i.hasExtra("text")) setClip(i.getStringExtra("text"), "intent"); return START_STICKY; }
    public void onDestroy() { running=false; try{ if(server!=null) server.close(); }catch(Exception e){} super.onDestroy(); }

    void startFg() {
        if(Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel("sync", "MichAutoClipSync", NotificationManager.IMPORTANCE_LOW);
            ((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
        }
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, "sync") : new Notification.Builder(this);
        b.setContentTitle("MichAutoClipSync").setContentText("LAN clipboard bridge active on port 8765").setSmallIcon(com.mich.autoclipsync.R.drawable.ic_mich_auto_clip_sync_notify).setOngoing(true);
        startForeground(42, b.build());
    }

    void listen() { try { cm.addPrimaryClipChangedListener(new ClipboardManager.OnPrimaryClipChangedListener(){ public void onPrimaryClipChanged(){ readClip("listener"); }}); } catch(Exception e){ lastSource="listener_error:"+e.getClass().getSimpleName(); } }
    void startPoll() { Thread t=new Thread(new Runnable(){ public void run(){ while(running){ readClip("poll"); try{Thread.sleep(500);}catch(Exception e){} } }}); t.setDaemon(true); t.start(); }
    static String esc(String s) { if(s==null) return ""; return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r"); }
    static String sha(byte[] data) { try { MessageDigest md=MessageDigest.getInstance("SHA-256"); byte[] d=md.digest(data); StringBuilder sb=new StringBuilder(); for(byte b:d) sb.append(String.format("%02x", b & 255)); return sb.toString(); } catch(Throwable t){ return ""; } }
    static byte[] readAll(InputStream in) throws java.io.IOException { try { ByteArrayOutputStream bos=new ByteArrayOutputStream(); byte[] buf=new byte[8192]; int n; while((n=in.read(buf))!=-1) bos.write(buf,0,n); return bos.toByteArray(); } finally { try{in.close();}catch(Exception e){} } }
    public static void publishObservedText(String text, String src) { if(text==null) text=""; if(!text.equals(lastText) || !"text".equals(lastKind)){ lastText=text; lastChange=System.currentTimeMillis(); lastSource=src; lastKind="text"; } lastClipboardRead=System.currentTimeMillis(); lastClipboardReadError=""; }
    public static void publishObservedImage(byte[] image, String src) { if(image==null) image=new byte[0]; String h=sha(image); if(image.length>0 && !h.equals(lastImageHash)){ lastImage=image; lastImageHash=h; lastChange=System.currentTimeMillis(); lastSource=src; lastKind="image"; } lastClipboardRead=System.currentTimeMillis(); lastClipboardReadError=""; }
    public static boolean publishClipData(Context context, ClipData clip, String src) {
        try {
            if(context==null || clip==null || clip.getItemCount()==0) return false;
            ClipData.Item item=clip.getItemAt(0);
            Uri u=item.getUri();
            if(u!=null) {
                try {
                    byte[] img=readAll(context.getContentResolver().openInputStream(u));
                    if(img.length>0) { publishObservedImage(img, src); return true; }
                } catch(Throwable ignored) {}
            }
            CharSequence cs=item.coerceToText(context);
            String text=cs==null?"":cs.toString();
            publishObservedText(text, src);
            return true;
        } catch(Throwable t) {
            lastClipboardReadError=src+"_publish_blocked:"+t.getClass().getSimpleName();
            lastSource=lastClipboardReadError;
            return false;
        }
    }
    public static void publishAccessibilityState(String src, String error) { accessibilityRunning=true; lastAccessibilitySeen=System.currentTimeMillis(); lastAccessibilitySource=src==null?"":src; lastAccessibilityError=error==null?"":error; }
    public static void publishAccessibilityEventDebug(String event, String selection) { lastAccessibilityEvent=event==null?"":event; if(selection!=null && selection.length()>0){ lastAccessibilitySelection=selection; lastAccessibilitySelectionSeen=System.currentTimeMillis(); } }
    public static void publishAccessibilityStopped(String src) { accessibilityRunning=false; lastAccessibilitySeen=System.currentTimeMillis(); lastAccessibilitySource=src==null?"":src; }
    public static void publishSemClipboardState(boolean available, boolean active, String src, String error, String klass) { semClipboardAvailable=available; semClipboardRunning=active; lastSemClipboardSeen=System.currentTimeMillis(); lastSemClipboardSource=src==null?"":src; lastSemClipboardError=error==null?"":error; if(klass!=null && klass.length()>0) semClipboardClass=klass; }
    public static void publishSemClipboardDetails(int count, String classes, String event) { semClipboardClipCount=count; semClipboardClipClasses=classes==null?"":classes; if(event!=null && event.length()>0){ lastSemClipboardEvent=event; semClipboardEventCount++; } }
    public static void publishSemClipboardEventArgs(String args) { lastSemClipboardEventArgs=args==null?"":args; }
    public static void publishSemClipboardMethods(String methods) { semClipboardMethods=methods==null?"":methods; }
    public static void publishMediaImageState(boolean running, String src, String error, String name) { mediaImageObserverRunning=running; lastMediaImageSeen=System.currentTimeMillis(); lastMediaImageSource=src==null?"":src; lastMediaImageError=error==null?"":error; if(name!=null && name.length()>0) lastMediaImageName=name; }
    void readClip(String src) { try { if(cm!=null && cm.hasPrimaryClip()) { ClipData cd=cm.getPrimaryClip(); publishClipData(this, cd, src); } lastClipboardRead=System.currentTimeMillis(); lastClipboardReadError=""; } catch(Throwable t){ lastClipboardReadError=src+"_blocked:"+t.getClass().getSimpleName(); lastSource=lastClipboardReadError; } }
    void startSamsungClipboardObserver() { try { samsungClipboardObserver=new SamsungClipboardObserver(this); samsungClipboardObserver.start(); } catch(Throwable t){ publishSemClipboardState(false,false,"semclipboard_start_blocked",t.getClass().getSimpleName(),""); } }
    void startAndroidImageObserver() { try { androidImageObserver=new AndroidImageObserver(this); androidImageObserver.start(); } catch(Throwable t){ publishMediaImageState(false,"media_image_start_blocked",t.getClass().getSimpleName(),""); } }
    public static void externalSet(Context c, String text) { if(instance!=null) instance.setClip(text, "broadcast"); else { Intent i=new Intent(c, ClipBridgeService.class); i.putExtra("text", text); if(Build.VERSION.SDK_INT>=26)c.startForegroundService(i); else c.startService(i); } }
    void setClip(String text, String src) { try { if(text==null) text=""; cm.setPrimaryClip(ClipData.newPlainText("MichAutoClipSync", text)); publishObservedText(text, src); } catch(Throwable t){ lastSource=src+"_set_blocked:"+t.getClass().getSimpleName(); } }
    void setImage(byte[] image, String src) { try { if(image==null || image.length==0) return; File f=new File(getCacheDir(),"mich_autoclip_clipboard.png"); FileOutputStream fos=new FileOutputStream(f); fos.write(image); fos.close(); Uri uri=Uri.parse("content://"+getPackageName()+".imageprovider/clipboard/mich_autoclip_clipboard.png"); ClipData cd=ClipData.newUri(getContentResolver(),"MichAutoClipSync image",uri); cm.setPrimaryClip(cd); publishObservedImage(image, src); } catch(Throwable t){ lastSource=src+"_image_set_blocked:"+t.getClass().getSimpleName(); } }

    void startBeacon() { Thread t=new Thread(new Runnable(){ public void run(){ while(running){ try { byte[] data=("MICH_AUTO_CLIP_SYNC 8765 com.mich.autoclipsync "+System.currentTimeMillis()).getBytes(StandardCharsets.UTF_8); DatagramSocket ds=new DatagramSocket(); ds.setBroadcast(true); DatagramPacket p=new DatagramPacket(data,data.length,InetAddress.getByName("255.255.255.255"),18766); ds.send(p); ds.close(); } catch(Throwable e){} try{Thread.sleep(2000);}catch(Exception e){} } }}); t.setDaemon(true); t.start(); }

    void startHttp() { Thread t=new Thread(new Runnable(){ public void run(){ try { server=new ServerSocket(8765,50, InetAddress.getByName("0.0.0.0")); while(running) handle(server.accept()); } catch(Exception e){ lastSource="http_error:"+e.getClass().getSimpleName(); } }}); t.setDaemon(true); t.start(); }
    void handle(Socket s) {
        try {
            s.setSoTimeout(3000);
            BufferedInputStream in = new BufferedInputStream(s.getInputStream());
            ByteArrayOutputStream head = new ByteArrayOutputStream();
            int prev=0,b;
            while((b=in.read())!=-1){ head.write(b); if(prev=='\r' && b=='\n'){ byte[] h=head.toByteArray(); int n=h.length; if(n>=4 && h[n-4]=='\r' && h[n-3]=='\n' && h[n-2]=='\r' && h[n-1]=='\n') break; } prev=b; }
            String hs=head.toString("UTF-8"); String[] lines=hs.split("\r?\n"); String first=lines.length>0?lines[0]:""; int len=0;
            for(String l:lines){ int idx=l.indexOf(':'); if(idx>0 && l.substring(0,idx).equalsIgnoreCase("Content-Length")) len=Integer.parseInt(l.substring(idx+1).trim()); }
            byte[] body=new byte[len]; int off=0; while(off<len){ int r=in.read(body,off,len-off); if(r<0)break; off+=r; }
            String[] parts=first.split(" "); String method=parts.length>0?parts[0]:"GET"; String path=parts.length>1?parts[1]:"/"; String resp; String type="text/plain; charset=utf-8"; int code=200;
            if(path.startsWith("/status")){ type="application/json"; long now=System.currentTimeMillis(); resp="{\"ok\":true,\"transport\":\"lan\",\"port\":8765,\"serviceStarted\":"+serviceStarted+",\"lastChange\":"+lastChange+",\"lastSource\":\""+esc(lastSource)+"\",\"kind\":\""+esc(lastKind)+"\",\"length\":"+(lastText==null?0:lastText.length())+",\"imageLength\":"+(lastImage==null?0:lastImage.length)+",\"imageHash\":\""+esc(lastImageHash)+"\",\"lastClipboardRead\":"+lastClipboardRead+",\"lastClipboardReadError\":\""+esc(lastClipboardReadError)+"\",\"accessibilityRunning\":"+accessibilityRunning+",\"lastAccessibilitySeen\":"+lastAccessibilitySeen+",\"accessibilityAgeMs\":"+(lastAccessibilitySeen==0?999999999:(now-lastAccessibilitySeen))+",\"lastAccessibilitySource\":\""+esc(lastAccessibilitySource)+"\",\"lastAccessibilityError\":\""+esc(lastAccessibilityError)+"\",\"lastAccessibilityEvent\":\""+esc(lastAccessibilityEvent)+"\",\"lastAccessibilitySelection\":\""+esc(lastAccessibilitySelection)+"\",\"lastAccessibilitySelectionAgeMs\":"+(lastAccessibilitySelectionSeen==0?999999999:(now-lastAccessibilitySelectionSeen))+",\"semClipboardAvailable\":"+semClipboardAvailable+",\"semClipboardRunning\":"+semClipboardRunning+",\"lastSemClipboardSeen\":"+lastSemClipboardSeen+",\"semClipboardAgeMs\":"+(lastSemClipboardSeen==0?999999999:(now-lastSemClipboardSeen))+",\"lastSemClipboardSource\":\""+esc(lastSemClipboardSource)+"\",\"lastSemClipboardError\":\""+esc(lastSemClipboardError)+"\",\"semClipboardClass\":\""+esc(semClipboardClass)+"\",\"semClipboardClipCount\":"+semClipboardClipCount+",\"semClipboardClipClasses\":\""+esc(semClipboardClipClasses)+"\",\"semClipboardEventCount\":"+semClipboardEventCount+",\"lastSemClipboardEvent\":\""+esc(lastSemClipboardEvent)+"\",\"lastSemClipboardEventArgs\":\""+esc(lastSemClipboardEventArgs)+"\",\"lastSemClipboardPublish\":"+lastSemClipboardPublish+",\"semClipboardMethods\":\""+esc(semClipboardMethods)+"\",\"mediaImageObserverRunning\":"+mediaImageObserverRunning+",\"lastMediaImageSeen\":"+lastMediaImageSeen+",\"mediaImageAgeMs\":"+(lastMediaImageSeen==0?999999999:(now-lastMediaImageSeen))+",\"lastMediaImageSource\":\""+esc(lastMediaImageSource)+"\",\"lastMediaImageError\":\""+esc(lastMediaImageError)+"\",\"lastMediaImageName\":\""+esc(lastMediaImageName)+"\"}"; }
            else if(path.startsWith("/clip") && method.equals("GET")){ resp=lastText==null?"":lastText; }
            else if(path.startsWith("/clip") && method.equals("POST")){ String txt=new String(body,0,off, StandardCharsets.UTF_8); setClip(txt,"http"); resp="OK "+txt.length(); }
            else if(path.startsWith("/image") && method.equals("GET")){ byte[] img=lastImage==null?new byte[0]:lastImage; OutputStream out=s.getOutputStream(); out.write(("HTTP/1.1 "+(img.length>0?200:204)+" OK\r\nContent-Type: image/png\r\nContent-Length: "+img.length+"\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8)); out.write(img); out.flush(); try{s.close();}catch(Exception e){} return; }
            else if(path.startsWith("/image") && method.equals("POST")){ byte[] img=new byte[off]; System.arraycopy(body,0,img,0,off); setImage(img,"http"); resp="OK_IMAGE "+img.length; }
            else { code=404; resp="not found"; }
            byte[] rb=resp.getBytes(StandardCharsets.UTF_8); OutputStream out=s.getOutputStream(); out.write(("HTTP/1.1 "+code+" OK\r\nContent-Type: "+type+"\r\nContent-Length: "+rb.length+"\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8)); out.write(rb); out.flush();
        } catch(Exception e) {}
        try { s.close(); } catch(Exception e) {}
    }
}
